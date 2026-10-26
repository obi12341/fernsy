import AppKit
import FernsyCore
import Foundation

struct Recording: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        case scheduled, recording, done, failed, skipped, missed
    }

    let id: UUID
    let channelId: Int
    var channelName: String
    var title: String
    var description: String
    /// The show's times; the recording runs from `start - padBefore` to `end + padAfter`.
    var start: Date
    var end: Date
    var padBefore: TimeInterval
    var padAfter: TimeInterval
    /// Padding follows Settings while scheduled (planned from program data). False for
    /// recordings without program data and for explicitly given padding.
    var followsPaddingSettings = true
    var status: Status
    var fileName: String?
    var error: String?
    var bytes: Int64?
    /// Seconds taken off the padding so the recordings fit the account's streams
    /// (`Recorder.rebalance`); the configured padding stays, so it comes back when the
    /// neighbour goes.
    var clipBefore: TimeInterval = 0
    var clipAfter: TimeInterval = 0
    /// Content the provider did not deliver (10 s or more each), saved as each gap closes.
    var gaps: [Gap] = []

    typealias Gap = RecordingGap

    var recordStart: Date { start.addingTimeInterval(-padBefore + clipBefore) }
    var recordEnd: Date { end.addingTimeInterval(padAfter - clipAfter) }

    var isUpcomingOrRunning: Bool { status == .scheduled || status == .recording }

    func matches(channelId: Int, entry: EPGEntry) -> Bool {
        self.channelId == channelId && abs(start.timeIntervalSince(entry.start)) < 60 && title == entry.title
    }
}

extension Recording {
    private enum CodingKeys: String, CodingKey {
        case id, channelId, channelName, title, description, start, end, padBefore, padAfter
        case followsPaddingSettings, status, fileName, error, bytes, clipBefore, clipAfter, gaps
    }

    /// Lists written before `followsPaddingSettings` existed: their scheduled entries follow
    /// the settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        channelId = try c.decode(Int.self, forKey: .channelId)
        channelName = try c.decode(String.self, forKey: .channelName)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decode(String.self, forKey: .description)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        padBefore = try c.decode(TimeInterval.self, forKey: .padBefore)
        padAfter = try c.decode(TimeInterval.self, forKey: .padAfter)
        followsPaddingSettings = try c.decodeIfPresent(Bool.self, forKey: .followsPaddingSettings) ?? true
        status = try c.decode(Status.self, forKey: .status)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        bytes = try c.decodeIfPresent(Int64.self, forKey: .bytes)
        clipBefore = try c.decodeIfPresent(TimeInterval.self, forKey: .clipBefore) ?? 0
        clipAfter = try c.decodeIfPresent(TimeInterval.self, forKey: .clipAfter) ?? 0
        gaps = try c.decodeIfPresent([Gap].self, forKey: .gaps) ?? []
    }
}

/// Scheduled and finished recordings of the signed-in account, and the recordings in
/// progress. Recordings run inside the app: Fernsy has to be open (the Mac is kept awake
/// while one runs or is about to start).
@MainActor
final class Recorder: ObservableObject {
    @Published private(set) var recordings: [Recording] = []

    weak var app: AppModel?
    private var storeURL: URL?
    private var copiers: [UUID: RecordingCopier] = [:]
    private var gapTrackers: [UUID: GapTracker] = [:]
    private var gapTimer: Timer?
    private var starting: Set<UUID> = []
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var activityReason: String?

    /// Connect this early, so the recording has data from its first second.
    static let tuneAhead: TimeInterval = 20
    static let padBeforeKey = "recording.padBefore"
    static let padAfterKey = "recording.padAfter"
    /// Hours before a scheduled recording from which the Mac is kept from idle sleep:
    /// 0 keeps it awake while any recording is scheduled, -1 never (not even while recording).
    static let keepAwakeHoursKey = "recording.keepAwakeHours"
    static let keepAwakeChoices = [-1, 1, 3, 6, 12, 24, 0]

    private var defaultsObserver: NSObjectProtocol?
    private var appliedPadding: (before: TimeInterval, after: TimeInterval) = (0, 0)

    init() {
        UserDefaults.standard.register(defaults: [Self.padBeforeKey: 10, Self.padAfterKey: 10, Self.keepAwakeHoursKey: 6])
        #if DEBUG
        // IPTV_AWAKEHOURS=<hours|0|off>: the keep-awake setting for this run, in memory only.
        if let value = ProcessInfo.processInfo.environment["IPTV_AWAKEHOURS"] {
            debugKeepAwakeHours = value == "off" ? -1 : Int(value)
        }
        #endif
        appliedPadding = (padBefore, padAfter)
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateActivity()
                let current = (self.padBefore, self.padAfter)
                guard current != self.appliedPadding else { return }
                self.applyPadding(before: current.0, after: current.1)
            }
        }
    }

    /// Settings changed: scheduled recordings planned from program data take the new padding.
    /// Running and finished recordings keep their window.
    func applyPadding(before: TimeInterval, after: TimeInterval) {
        appliedPadding = (before, after)
        var changed = false
        for i in recordings.indices where recordings[i].status == .scheduled && recordings[i].followsPaddingSettings {
            guard recordings[i].padBefore != before || recordings[i].padAfter != after else { continue }
            recordings[i].padBefore = before
            recordings[i].padAfter = after
            changed = true
        }
        guard changed else { return }
        AppLog.info(.recordings, "padding now \(Int(before / 60))/\(Int(after / 60)) min for scheduled recordings")
        rebalance()
        save()
        tick()
    }

    /// ~/Movies/Fernsy (the real one, not the sandbox container's); debug builds use
    /// ~/Movies/Fernsy Dev, next to the installed app's recordings.
    static var folder: URL {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? NSHomeDirectory()
        #if DEBUG
        let name = "Movies/Fernsy Dev"
        #else
        let name = "Movies/Fernsy"
        #endif
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(name, isDirectory: true)
    }

    func fileURL(_ recording: Recording) -> URL? {
        recording.fileName.map { Self.folder.appendingPathComponent($0) }
    }

    // MARK: Account

    /// Loads the recordings of `accountKey` (nil: signed out, everything stops).
    func activate(accountKey: String?) {
        stopAll(reason: nil)
        timer?.invalidate()
        timer = nil
        gapTimer?.invalidate()
        gapTimer = nil
        recordings = []
        storeURL = nil
        guard let accountKey else { updateActivity(); return }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Fernsy/\(accountKey)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storeURL = dir.appendingPathComponent("recordings.json")
        if let data = storeURL.flatMap({ try? Data(contentsOf: $0) }),
           let saved = try? JSONDecoder().decode([Recording].self, from: data) {
            // Recordings that were running when the app last quit end with what they got.
            recordings = saved.map { r in
                var r = r
                if r.status == .recording {
                    r.status = fileURL(r).map { FileManager.default.fileExists(atPath: $0.path) } == true ? .done : .failed
                    r.bytes = fileURL(r).flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int64 }
                    if r.fileName == nil { r.error = String(localized: "No data from the channel") }
                }
                return r
            }
        }
        AppLog.detail(.recordings, "\(recordings.count) recordings loaded for this account")
        rebalance()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        let gapTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleGaps() }
        }
        RunLoop.main.add(gapTimer, forMode: .common)
        self.gapTimer = gapTimer
        tick()
    }

    private func save() {
        publishGrowing()
        guard let storeURL, let data = try? JSONEncoder().encode(recordings) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func update(_ id: UUID, _ change: (inout Recording) -> Void) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        change(&recordings[i])
        save()
    }

    // MARK: Queries

    func recording(channelId: Int, entry: EPGEntry) -> Recording? {
        recordings.last { $0.matches(channelId: channelId, entry: entry) && $0.status != .skipped }
    }

    /// The recording running on this channel right now.
    func active(on channelId: Int) -> Recording? {
        recordings.first { $0.channelId == channelId && $0.status == .recording }
    }

    var hasActiveOrUpcoming: Bool {
        recordings.contains { $0.status == .recording || ($0.status == .scheduled && $0.recordStart < Date().addingTimeInterval(24 * 3600)) }
    }

    /// Whether a recording's file is still being written; read by the player's demux thread.
    nonisolated static func isGrowing(_ id: UUID) -> Bool {
        growingLock.lock(); defer { growingLock.unlock() }
        return growingIDs.contains(id)
    }

    nonisolated private static let growingLock = NSLock()
    nonisolated(unsafe) private static var growingIDs = Set<UUID>()

    private func publishGrowing() {
        let ids = Set(recordings.filter { $0.status == .recording }.map(\.id))
        Self.growingLock.lock()
        Self.growingIDs = ids
        Self.growingLock.unlock()
    }

    // MARK: Scheduling

    private var padBefore: TimeInterval { Double(UserDefaults.standard.integer(forKey: Self.padBeforeKey)) * 60 }
    private var padAfter: TimeInterval { Double(UserDefaults.standard.integer(forKey: Self.padAfterKey)) * 60 }

    enum PlanResult {
        /// Planned; the notice names paddings shortened for it.
        case planned(notice: String?)
        /// Not planned: the shows would need more streams than the account has.
        case refused(String)
    }

    private var limit: Int { app?.tuners.limit ?? 1 }

    /// Plans a show (running or future), unless the shows' own times would need more streams
    /// than the account allows.
    @discardableResult
    func schedule(_ entry: EPGEntry, on channel: LiveChannel, padding: (before: TimeInterval, after: TimeInterval)? = nil) -> PlanResult {
        if let existing = recording(channelId: channel.id, entry: entry), existing.isUpcomingOrRunning { return .planned(notice: nil) }
        let recording = Recording(id: UUID(), channelId: channel.id, channelName: channel.recordingLabel, title: entry.title,
                                  description: entry.description, start: entry.start, end: entry.end,
                                  padBefore: padding?.before ?? padBefore, padAfter: padding?.after ?? padAfter,
                                  followsPaddingSettings: padding == nil, status: .scheduled)
        return plan(recording)
    }

    /// Player: records the show that is on now (from its start, as far as the timeshift
    /// buffer reaches back), or the next two hours without programme data.
    @discardableResult
    func recordNow(_ channel: LiveChannel, entry: EPGEntry?) -> PlanResult {
        if let entry { return schedule(entry, on: channel) }
        let now = Date()
        let recording = Recording(id: UUID(), channelId: channel.id, channelName: channel.recordingLabel,
                                  title: String(localized: "Recording \(now.formatted(date: .abbreviated, time: .shortened))"),
                                  description: "", start: now, end: now.addingTimeInterval(2 * 3600),
                                  padBefore: 0, padAfter: 0, followsPaddingSettings: false, status: .scheduled)
        return plan(recording)
    }

    private func plan(_ recording: Recording) -> PlanResult {
        let limit = limit
        let others = recordings.filter(\.isUpcomingOrRunning).map(planItem)
        let inTheWay = RecordingPlan.blockers(for: planItem(recording), among: others, limit: limit, now: Date())
            .compactMap { id in recordings.first { $0.id == id } }
        guard inTheWay.isEmpty else {
            let names = inTheWay.map { String(localized: "“\($0.title)” (\($0.channelName))") }.joined(separator: ", ")
            AppLog.info(.recordings, "refused \(recording.title) on \(recording.channelName): overlaps \(names) with \(limit) stream(s)")
            return .refused(String(localized: "“\(recording.title)” is on at the same time as \(names). Your account allows \(limit) stream(s) at a time. Remove one of these recordings to record this show."))
        }
        recordings.append(recording)
        let previous = rebalance()
        save()
        tick()
        var lines: [String] = []
        for r in recordings where r.isUpcomingOrRunning {
            let old = previous[r.id] ?? (before: 0, after: 0)
            if r.clipAfter > old.after {
                lines.append(String(localized: "Record after for “\(r.title)” shortened to \(Int(((r.padAfter - r.clipAfter) / 60).rounded())) min."))
            }
            if r.clipBefore > old.before {
                lines.append(String(localized: "Record before for “\(r.title)” shortened to \(Int(((r.padBefore - r.clipBefore) / 60).rounded())) min."))
            }
        }
        if let planned = recordings.first(where: { $0.id == recording.id }) {
            AppLog.info(.recordings, "planned \(planned.title) on \(planned.channelName): \(Self.window(planned))")
        }
        guard !lines.isEmpty else { return .planned(notice: nil) }
        let notice = String(localized: "Your account allows \(limit) stream(s) at a time, so less extra time is possible:") + "\n" + lines.joined(separator: "\n")
        return .planned(notice: notice)
    }

    /// Shortens padding where it would need more streams than the account allows (see
    /// `RecordingPlan`), after any change to the plan, the padding or the limit. Returns the
    /// clips from before, so planning can say what got shorter.
    @discardableResult
    func rebalance() -> [UUID: (before: TimeInterval, after: TimeInterval)] {
        let previous = Dictionary(uniqueKeysWithValues: recordings.map { ($0.id, (before: $0.clipBefore, after: $0.clipAfter)) })
        let now = Date()
        let windows = RecordingPlan.windows(for: recordings.filter(\.isUpcomingOrRunning).map(planItem), limit: limit, now: now)
        var changed: [Recording] = []
        for i in recordings.indices where recordings[i].isUpcomingOrRunning {
            let r = recordings[i]
            guard let window = windows[r.id] else { continue }
            // A window that has already begun keeps its start.
            let before = r.recordStart <= now ? r.clipBefore : max(0, window.start.timeIntervalSince(r.start.addingTimeInterval(-r.padBefore)))
            let after = max(0, r.end.addingTimeInterval(r.padAfter).timeIntervalSince(window.end))
            guard before != r.clipBefore || after != r.clipAfter else { continue }
            recordings[i].clipBefore = before
            recordings[i].clipAfter = after
            changed.append(recordings[i])
        }
        if !changed.isEmpty {
            for r in changed { AppLog.info(.recordings, "window of \(r.title) on \(r.channelName) now \(Self.window(r)) (\(limit) stream(s))") }
            save()
        }
        return previous
    }

    private func planItem(_ r: Recording) -> RecordingPlan.Item {
        let begun = r.status == .recording || r.recordStart <= Date()
        return RecordingPlan.Item(id: r.id, channelId: r.channelId, start: r.start, end: r.end, padBefore: r.padBefore,
                                  padAfter: r.padAfter, runningSince: begun ? r.recordStart : nil)
    }

    private static func window(_ r: Recording) -> String {
        "\(r.recordStart.formatted(date: .omitted, time: .shortened))–\(r.recordEnd.formatted(date: .omitted, time: .shortened))"
            + " (show \(r.start.formatted(date: .omitted, time: .shortened))–\(r.end.formatted(date: .omitted, time: .shortened)))"
    }

    /// Stops a running recording now (keeping what was recorded) or drops a scheduled one.
    func stop(_ id: UUID) {
        guard let recording = recordings.first(where: { $0.id == id }) else { return }
        switch recording.status {
        case .recording: finish(id, error: nil)
        case .scheduled: recordings.removeAll { $0.id == id }; rebalance(); save()
        default: break
        }
    }

    /// Removes a recording from the list and moves its file to the trash.
    func delete(_ id: UUID) {
        guard let recording = recordings.first(where: { $0.id == id }) else { return }
        if recording.status == .recording { finish(id, error: nil) }
        if let url = fileURL(recording) { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        recordings.removeAll { $0.id == id }
        rebalance()
        save()
    }

    func unschedule(channelId: Int, entry: EPGEntry) {
        guard let recording = recording(channelId: channelId, entry: entry) else { return }
        stop(recording.id)
    }

    // MARK: Running

    private func tick() {
        let now = Date()
        for recording in recordings {
            switch recording.status {
            case .scheduled where now >= recording.recordEnd:
                update(recording.id) { $0.status = .missed }
            case .scheduled where now >= recording.recordStart.addingTimeInterval(-Self.tuneAhead):
                begin(recording)
            case .recording where now >= recording.recordEnd:
                finish(recording.id, error: nil)
            case .recording:
                // The connection is gone for good (offline channel, account blocked).
                if let tuner = app?.tuners.tuner(recording.channelId), !tuner.isActive {
                    let reason: String
                    if case .failed(let message) = tuner.state { reason = message } else { reason = String(localized: "Connection lost") }
                    finish(recording.id, error: reason)
                }
            default:
                break
            }
        }
        updateActivity()
    }

    private func begin(_ recording: Recording) {
        guard let app, !starting.contains(recording.id), let url = app.client?.liveURL(recording.channelId) else { return }
        starting.insert(recording.id)
        Task {
            defer { starting.remove(recording.id) }
            await handOver(to: recording.id)
            guard let recording = recordings.first(where: { $0.id == recording.id }) else { return }
            guard await resolveConflicts(for: recording) else {
                update(recording.id) { $0.status = .skipped }
                return
            }
            guard recordings.first(where: { $0.id == recording.id })?.status == .scheduled else { return }
            let tuner = app.tuners.acquire(recording.channelId, url: url, owner: .recording(recording.id))
            // Running from now on, with or without data: the list shows it waiting, and it can be
            // stopped. Waits for the start time and the first data (so the file starts on a
            // keyframe) until the window ends; the tuner keeps reconnecting meanwhile.
            update(recording.id) { $0.status = .recording }
            while isWaiting(recording.id) && (tuner.buffer.newest == nil || Date() < recording.recordStart)
                    && Date() < recording.recordEnd && tuner.state != .unsupported {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard isWaiting(recording.id) else {
                // Stopped or finished meanwhile (finish released the tuner).
                return
            }
            guard tuner.state != .unsupported, let entry = tuner.buffer.entry(atOrBeforeWall: recording.recordStart) else {
                finish(recording.id, error: tuner.state == .unsupported ? PlayerError.unsupported.localizedDescription : nil)
                return
            }
            let name = Self.fileName(for: recording)
            do {
                try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                let copier = try RecordingCopier(buffer: tuner.buffer, from: entry.offset, to: Self.folder.appendingPathComponent(name))
                copiers[recording.id] = copier
                gapTrackers[recording.id] = GapTracker()
                update(recording.id) { $0.fileName = name }
                AppLog.info(.recordings, "started \(recording.title) on \(recording.channelName) → \(name)")
            } catch {
                finish(recording.id, error: error.localizedDescription)
            }
        }
    }

    /// Once a second: how much content each writing recording got against the clock.
    private func sampleGaps() {
        guard !gapTrackers.isEmpty else { return }
        let now = Date()
        for id in Array(gapTrackers.keys) {
            guard let recording = recordings.first(where: { $0.id == id }),
                  let content = app?.tuners.tuner(recording.channelId)?.contentTime,
                  let gap = gapTrackers[id]?.sample(wall: now, content: content) else { continue }
            add(gap, to: recording)
        }
    }

    private func add(_ gap: Recording.Gap, to recording: Recording) {
        update(recording.id) { $0.gaps.append(gap) }
        AppLog.warning(.recordings, "\(recording.title): \(Int(gap.seconds)) s missing from \(gap.at.formatted(date: .omitted, time: .standard)), the provider delivered too little")
    }

    /// Started (status `.recording`) but not writing yet, because no data has arrived.
    private func isWaiting(_ id: UUID) -> Bool {
        recordings.first { $0.id == id }?.status == .recording && copiers[id] == nil
    }

    private func finish(_ id: UUID, error: String?) {
        guard let recording = recordings.first(where: { $0.id == id }) else { return }
        let tuner = app?.tuners.tuner(recording.channelId)
        if var tracker = gapTrackers.removeValue(forKey: id), let gap = tracker.finish() { add(gap, to: recording) }
        if let copier = copiers.removeValue(forKey: id) {
            copier.onFinish = { [weak self, weak copier] in
                guard let self else { return }
                self.update(id) {
                    $0.bytes = copier?.bytesWritten
                    if let failure = copier?.error ?? error { $0.error = failure }
                }
            }
            copier.finish(at: tuner?.buffer.endOffset ?? 0)
        }
        // Waited the whole time (or was stopped while waiting) without any data.
        let error = recording.fileName == nil ? error ?? String(localized: "No data from the channel") : error
        update(id) {
            $0.status = error == nil ? .done : .failed
            $0.error = error
            // A recording stopped early ends now.
            if Date() < $0.recordEnd { $0.end = max($0.start, Date()); $0.padAfter = 0; $0.clipAfter = 0 }
        }
        app?.tuners.release(recording.channelId, owner: .recording(id))
        rebalance()
        if let error {
            AppLog.error(.recordings, "\(recording.title) on \(recording.channelName) failed: \(error)")
        } else {
            AppLog.info(.recordings, "finished \(recording.title) on \(recording.channelName)")
        }
    }

    /// App quit or sign-out: everything recorded so far is kept.
    func stopAll(reason: String?) {
        for recording in recordings where recording.status == .recording {
            finish(recording.id, error: reason)
        }
    }

    /// Writes out running recordings before the app quits.
    func flushForTermination() {
        let running = Array(copiers.values)
        stopAll(reason: nil)
        for copier in running { copier.waitUntilDone() }
    }

    // MARK: Conflicts

    /// Back to back on another channel: when everything in the way is a recording whose
    /// window ends where this one begins, wait for that moment, end those recordings exactly
    /// then and take over their connection, without tuning in early and without asking.
    private func handOver(to id: UUID) async {
        guard let app, let recording = recordings.first(where: { $0.id == id }) else { return }
        let blockers = app.tuners.blockers(for: recording.channelId, as: .recording(id))
        guard !blockers.isEmpty else { return }
        var previous: [Recording] = []
        for owner in blockers.flatMap(\.owners) {
            guard case .recording(let otherID) = owner, let other = recordings.first(where: { $0.id == otherID }),
                  other.status == .recording, other.recordEnd <= recording.recordStart.addingTimeInterval(1) else { return }
            previous.append(other)
        }
        AppLog.info(.recordings, "\(recording.title) takes over from \(previous.map(\.title).joined(separator: ", ")) at \(recording.recordStart.formatted(date: .omitted, time: .standard))")
        while let current = recordings.first(where: { $0.id == id }), current.status == .scheduled, Date() < current.recordStart {
            try? await Task.sleep(for: .milliseconds(100))
        }
        for other in previous where recordings.first(where: { $0.id == other.id })?.status == .recording {
            finish(other.id, error: nil)
        }
    }

    /// Asks before taking the connection from the player or another recording. Without an
    /// answer within a minute the recording starts (it was planned for a reason).
    private func resolveConflicts(for recording: Recording) async -> Bool {
        guard let app else { return false }
        let blockers = app.tuners.blockers(for: recording.channelId, as: .recording(recording.id))
        guard !blockers.isEmpty else { return true }
        let blockingRecordings = recordings.filter { r in
            r.status == .recording && blockers.contains { $0.owners.contains(.recording(r.id)) }
        }
        let playerBlocks = blockers.contains { $0.owners.contains(.player) }

        let message: String
        let confirm: String
        if let other = blockingRecordings.first {
            message = String(localized: "“\(other.title)” is being recorded on \(other.channelName). Your account allows only \(app.tuners.limit) stream(s) at a time.")
            confirm = String(localized: "Stop “\(other.title)” and Record")
        } else {
            message = String(localized: "To record, Fernsy switches to \(recording.channelName), because your account allows only \(app.tuners.limit) stream(s) at a time.")
            confirm = String(localized: "Switch and Record")
        }
        let accepted = await Prompt.ask(
            title: String(localized: "Recording “\(recording.title)” Is Starting"),
            message: message + "\n\n" + String(localized: "Without an answer, the recording starts in one minute."),
            confirm: confirm, cancel: String(localized: "Skip Recording"), timeout: 60, timeoutAnswer: true)
        guard accepted else { return false }
        for other in blockingRecordings { finish(other.id, error: nil) }
        if playerBlocks, let channel = app.channel(recording.channelId) {
            app.play(channel, force: true)
        }
        return true
    }

    // MARK: Keeping the Mac awake

    private var debugKeepAwakeHours: Int?

    private var keepAwakeHours: Int {
        debugKeepAwakeHours ?? UserDefaults.standard.integer(forKey: Self.keepAwakeHoursKey)
    }

    /// Holds an activity against idle sleep while a recording runs or the next one starts within
    /// the set hours. Its reason names that recording, so `pmset -g assertions` explains it.
    private func updateActivity() {
        let hours = keepAwakeHours
        let reason: String?
        if hours < 0 {
            reason = nil
        } else if let running = recordings.first(where: { $0.status == .recording }) {
            reason = "Recording: \(running.title)"
        } else {
            let limit = hours == 0 ? Date.distantFuture : Date().addingTimeInterval(Double(hours) * 3600)
            let next = recordings.filter { $0.status == .scheduled && $0.recordStart < limit }.min { $0.recordStart < $1.recordStart }
            reason = next.map { "Recording scheduled: \($0.title) at \($0.recordStart.formatted(date: .abbreviated, time: .shortened))" }
        }
        guard reason != activityReason else { return }
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        activityReason = reason
        if let reason {
            activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .suddenTerminationDisabled], reason: reason)
            AppLog.info(.recordings, "keeping the Mac awake (\(hours < 1 ? "always" : "\(hours) h")): \(reason)")
        } else {
            AppLog.info(.recordings, hours < 0 ? "keep-awake off" : "the Mac may sleep again")
        }
    }

    // MARK: Files

    private static func fileName(for recording: Recording) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let stamp = formatter.string(from: recording.start)
        var base = "\(recording.channelName) – \(recording.title) (\(stamp))"
        base = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        var name = base + ".ts"
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path) {
            name = "\(base) \(n).ts"
            n += 1
        }
        return name
    }
}

extension Recorder.PlanResult {
    /// Tells the user when planning was refused or shortened padding; silent otherwise.
    @MainActor
    func present() {
        switch self {
        case .planned(nil): break
        case .planned(let notice?): Prompt.inform(title: String(localized: "Recording Scheduled"), message: notice)
        case .refused(let message): Prompt.inform(title: String(localized: "Can’t Record"), message: message)
        }
    }
}

/// App-modal questions shown as a sheet on the frontmost window.
@MainActor
enum Prompt {
    private static var busy = false

    /// `timeout`: answers `timeoutAnswer` by itself after that many seconds.
    static func ask(title: String, message: String, confirm: String, cancel: String,
                    timeout: TimeInterval? = nil, timeoutAnswer: Bool = false) async -> Bool {
        while busy { try? await Task.sleep(for: .milliseconds(200)) }
        busy = true
        defer { busy = false }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: cancel)
        AppActivation.activate()
        let window = NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) && $0.attachedSheet == nil }
        return await withCheckedContinuation { continuation in
            var answered = false
            let finish: (Bool) -> Void = { answer in
                guard !answered else { return }
                answered = true
                continuation.resume(returning: answer)
            }
            if let window {
                alert.beginSheetModal(for: window) { response in finish(response == .alertFirstButtonReturn) }
                if let timeout {
                    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                        guard !answered else { return }
                        window.endSheet(alert.window, returnCode: timeoutAnswer ? .alertFirstButtonReturn : .alertSecondButtonReturn)
                    }
                }
            } else {
                // No window open: decide by the timeout answer, without blocking anything.
                if timeout != nil { finish(timeoutAnswer) } else { finish(alert.runModal() == .alertFirstButtonReturn) }
            }
        }
    }

    static func inform(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}

