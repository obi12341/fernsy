import FernsyCore
import Foundation

public struct Recording: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case scheduled, recording, done, failed, skipped, missed
    }

    public let id: UUID
    public let channelId: Int
    public var channelName: String
    public var title: String
    public var description: String
    /// The show's times; the recording runs from `start - padBefore` to `end + padAfter`.
    public var start: Date
    public var end: Date
    public var padBefore: TimeInterval
    public var padAfter: TimeInterval
    /// Padding follows Settings while scheduled (planned from program data). False for
    /// recordings without program data and for explicitly given padding.
    public var followsPaddingSettings = true
    public var status: Status
    public var fileName: String?
    public var error: String?
    public var bytes: Int64?
    /// Seconds taken off the padding so the recordings fit the account's streams
    /// (`Recorder.rebalance`); the configured padding stays, so it comes back when the
    /// neighbour goes.
    public var clipBefore: TimeInterval = 0
    public var clipAfter: TimeInterval = 0
    /// Content the provider did not deliver (10 s or more each), saved as each gap closes.
    public var gaps: [Gap] = []

    public typealias Gap = RecordingGap

    public var recordStart: Date { start.addingTimeInterval(-padBefore + clipBefore) }
    public var recordEnd: Date { end.addingTimeInterval(padAfter - clipAfter) }

    public var isUpcomingOrRunning: Bool { status == .scheduled || status == .recording }

    public func matches(channelId: Int, entry: EPGEntry) -> Bool {
        self.channelId == channelId && abs(start.timeIntervalSince(entry.start)) < 60 && title == entry.title
    }
}

extension Recording {
    private enum CodingKeys: String, CodingKey {
        case id, channelId, channelName, title, description, start, end, padBefore, padAfter
        case followsPaddingSettings, status, fileName, error, bytes, clipBefore, clipAfter, gaps
    }

    public init(id: UUID, channelId: Int, channelName: String, title: String, description: String, start: Date, end: Date,
                padBefore: TimeInterval, padAfter: TimeInterval, followsPaddingSettings: Bool = true, status: Status,
                fileName: String? = nil, error: String? = nil, bytes: Int64? = nil) {
        self.id = id
        self.channelId = channelId
        self.channelName = channelName
        self.title = title
        self.description = description
        self.start = start
        self.end = end
        self.padBefore = padBefore
        self.padAfter = padAfter
        self.followsPaddingSettings = followsPaddingSettings
        self.status = status
        self.fileName = fileName
        self.error = error
        self.bytes = bytes
    }

    /// Lists written before `followsPaddingSettings` existed: their scheduled entries follow
    /// the settings.
    public init(from decoder: Decoder) throws {
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

/// What the recorder needs from the app it runs in: connections, questions, storage and
/// keeping the device awake.
@MainActor
public protocol RecorderHost: AnyObject {
    var tuners: TunerPool { get }
    func liveURL(_ channelId: Int) -> URL?
    /// Plays the channel in the player, taking over the player's connection.
    func playForRecording(_ channelId: Int)
    /// A yes/no question; answers `timeoutAnswer` by itself after `timeout` seconds.
    func ask(title: String, message: String, confirm: String, cancel: String, timeout: TimeInterval, timeoutAnswer: Bool) async -> Bool
    /// Folder of the account's recordings list (`recordings.json`).
    func recordingsStore(accountKey: String) -> URL
    /// Folder the recording files are written to.
    var recordingsFolder: URL { get }
    /// Removes a deleted recording's file (the Mac moves it to the trash).
    func removeRecordingFile(_ url: URL)
    /// Holds the device awake with this reason, or lets it sleep again (nil).
    func keepAwake(reason: String?)
    /// Why a recording cannot start now (e.g. too little free space); nil: it can.
    func recordingRefusal() -> String?
    /// Drop finished entries whose file is gone (Apple TV: tvOS purged its caches).
    var dropsMissingRecordings: Bool { get }
}

public extension RecorderHost {
    func recordingRefusal() -> String? { nil }
    var dropsMissingRecordings: Bool { false }
}

/// When the device is kept awake for recordings.
public enum KeepAwakePolicy: Equatable, Sendable {
    case never
    /// Only while a recording runs.
    case whileRecording
    /// While one runs or the next starts within this many hours (nil: any scheduled one).
    case ahead(hours: Int?)
}

/// Scheduled and finished recordings of the signed-in account, and the recordings in
/// progress. Recordings run inside the app: Fernsy has to be open (the host keeps the device
/// awake while one runs or is about to start).
@MainActor
public final class Recorder: ObservableObject {
    @Published public private(set) var recordings: [Recording] = []

    public weak var host: RecorderHost?
    /// Read whenever the plan changes; the Mac follows its keep-awake setting.
    public var keepAwakePolicy: () -> KeepAwakePolicy = { .whileRecording }
    private var storeURL: URL?
    private var copiers: [UUID: RecordingCopier] = [:]
    private var gapTrackers: [UUID: GapTracker] = [:]
    private var gapTimer: Timer?
    private var starting: Set<UUID> = []
    private var timer: Timer?
    private var activityReason: String?

    /// Connect this early, so the recording has data from its first second.
    public static let tuneAhead: TimeInterval = 20
    public static let padBeforeKey = "recording.padBefore"
    public static let padAfterKey = "recording.padAfter"

    private var defaultsObserver: NSObjectProtocol?
    private var appliedPadding: (before: TimeInterval, after: TimeInterval) = (0, 0)

    public init() {
        UserDefaults.standard.register(defaults: [Self.padBeforeKey: 10, Self.padAfterKey: 10])
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
    public func applyPadding(before: TimeInterval, after: TimeInterval) {
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

    private var folder: URL? { host?.recordingsFolder }

    public func fileURL(_ recording: Recording) -> URL? {
        guard let folder else { return nil }
        return recording.fileName.map { folder.appendingPathComponent($0) }
    }

    // MARK: Account

    /// Loads the recordings of `accountKey` (nil: signed out, everything stops).
    public func activate(accountKey: String?) {
        stopAll(reason: nil)
        timer?.invalidate()
        timer = nil
        gapTimer?.invalidate()
        gapTimer = nil
        recordings = []
        storeURL = nil
        guard let accountKey else { updateActivity(); return }
        guard let dir = host?.recordingsStore(accountKey: accountKey) else { return }
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
                    if r.fileName == nil { r.error = String(localized: "No data from the channel", bundle: .module) }
                }
                return r
            }
            if host?.dropsMissingRecordings == true {
                let before = recordings.count
                recordings.removeAll { r in
                    guard r.status == .done || r.status == .failed, let url = fileURL(r) else { return false }
                    return !FileManager.default.fileExists(atPath: url.path)
                }
                if recordings.count < before {
                    AppLog.info(.recordings, "\(before - recordings.count) recordings removed: their files are gone")
                    save()
                }
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

    public func recording(channelId: Int, entry: EPGEntry) -> Recording? {
        recordings.last { $0.matches(channelId: channelId, entry: entry) && $0.status != .skipped }
    }

    /// The recording running on this channel right now.
    public func active(on channelId: Int) -> Recording? {
        recordings.first { $0.channelId == channelId && $0.status == .recording }
    }

    public var hasActiveOrUpcoming: Bool {
        recordings.contains { $0.status == .recording || ($0.status == .scheduled && $0.recordStart < Date().addingTimeInterval(24 * 3600)) }
    }

    /// Whether a recording's file is still being written; read by the player's demux thread.
    public nonisolated static func isGrowing(_ id: UUID) -> Bool {
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

    public enum PlanResult {
        /// Planned; the notice names paddings shortened for it.
        case planned(notice: String?)
        /// Not planned: the shows would need more streams than the account has.
        case refused(String)
    }

    private var limit: Int { host?.tuners.limit ?? 1 }

    /// Plans a show (running or future), unless the shows' own times would need more streams
    /// than the account allows.
    @discardableResult
    public func schedule(_ entry: EPGEntry, on channel: LiveChannel, padding: (before: TimeInterval, after: TimeInterval)? = nil) -> PlanResult {
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
    public func recordNow(_ channel: LiveChannel, entry: EPGEntry?) -> PlanResult {
        if let entry { return schedule(entry, on: channel) }
        let now = Date()
        let recording = Recording(id: UUID(), channelId: channel.id, channelName: channel.recordingLabel,
                                  title: String(localized: "Recording \(now.formatted(date: .abbreviated, time: .shortened))", bundle: .module),
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
            let names = inTheWay.map { String(localized: "“\($0.title)” (\($0.channelName))", bundle: .module) }.joined(separator: ", ")
            AppLog.info(.recordings, "refused \(recording.title) on \(recording.channelName): overlaps \(names) with \(limit) stream(s)")
            return .refused(String(localized: "“\(recording.title)” is on at the same time as \(names). Your account allows \(limit) stream(s) at a time. Remove one of these recordings to record this show.", bundle: .module))
        }
        recordings.append(recording)
        let previous = rebalance()
        save()
        tick()
        var lines: [String] = []
        for r in recordings where r.isUpcomingOrRunning {
            let old = previous[r.id] ?? (before: 0, after: 0)
            if r.clipAfter > old.after {
                lines.append(String(localized: "Record after for “\(r.title)” shortened to \(Int(((r.padAfter - r.clipAfter) / 60).rounded())) min.", bundle: .module))
            }
            if r.clipBefore > old.before {
                lines.append(String(localized: "Record before for “\(r.title)” shortened to \(Int(((r.padBefore - r.clipBefore) / 60).rounded())) min.", bundle: .module))
            }
        }
        if let planned = recordings.first(where: { $0.id == recording.id }) {
            AppLog.info(.recordings, "planned \(planned.title) on \(planned.channelName): \(Self.window(planned))")
        }
        guard !lines.isEmpty else { return .planned(notice: nil) }
        let notice = String(localized: "Your account allows \(limit) stream(s) at a time, so less extra time is possible:", bundle: .module) + "\n" + lines.joined(separator: "\n")
        return .planned(notice: notice)
    }

    /// Shortens padding where it would need more streams than the account allows (see
    /// `RecordingPlan`), after any change to the plan, the padding or the limit. Returns the
    /// clips from before, so planning can say what got shorter.
    @discardableResult
    public func rebalance() -> [UUID: (before: TimeInterval, after: TimeInterval)] {
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
    public func stop(_ id: UUID) {
        guard let recording = recordings.first(where: { $0.id == id }) else { return }
        switch recording.status {
        case .recording: finish(id, error: nil)
        case .scheduled: recordings.removeAll { $0.id == id }; rebalance(); save()
        default: break
        }
    }

    /// Removes a recording from the list and moves its file to the trash.
    public func delete(_ id: UUID) {
        guard let recording = recordings.first(where: { $0.id == id }) else { return }
        if recording.status == .recording { finish(id, error: nil) }
        if let url = fileURL(recording) { host?.removeRecordingFile(url) }
        recordings.removeAll { $0.id == id }
        rebalance()
        save()
    }

    public func unschedule(channelId: Int, entry: EPGEntry) {
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
                if let tuner = host?.tuners.tuner(recording.channelId), !tuner.isActive {
                    let reason: String
                    if case .failed(let message) = tuner.state { reason = message } else { reason = String(localized: "Connection lost", bundle: .module) }
                    finish(recording.id, error: reason)
                }
            default:
                break
            }
        }
        updateActivity()
    }

    private func begin(_ recording: Recording) {
        guard let host, let folder, !starting.contains(recording.id), let url = host.liveURL(recording.channelId) else { return }
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
            if let refusal = host.recordingRefusal() {
                update(recording.id) { $0.status = .failed; $0.error = refusal }
                AppLog.error(.recordings, "\(recording.title) on \(recording.channelName) not started: \(refusal)")
                return
            }
            let tuner = host.tuners.acquire(recording.channelId, url: url, owner: .recording(recording.id))
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
            let name = Self.fileName(for: recording, in: folder)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let copier = try RecordingCopier(buffer: tuner.buffer, from: entry.offset, to: folder.appendingPathComponent(name))
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
                  let content = host?.tuners.tuner(recording.channelId)?.contentTime,
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
        let tuner = host?.tuners.tuner(recording.channelId)
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
        let error = recording.fileName == nil ? error ?? String(localized: "No data from the channel", bundle: .module) : error
        update(id) {
            $0.status = error == nil ? .done : .failed
            $0.error = error
            // A recording stopped early ends now.
            if Date() < $0.recordEnd { $0.end = max($0.start, Date()); $0.padAfter = 0; $0.clipAfter = 0 }
        }
        host?.tuners.release(recording.channelId, owner: .recording(id))
        rebalance()
        if let error {
            AppLog.error(.recordings, "\(recording.title) on \(recording.channelName) failed: \(error)")
        } else {
            AppLog.info(.recordings, "finished \(recording.title) on \(recording.channelName)")
        }
    }

    /// App quit or sign-out: everything recorded so far is kept.
    public func stopAll(reason: String?) {
        for recording in recordings where recording.status == .recording {
            finish(recording.id, error: reason)
        }
    }

    /// Writes out running recordings before the app quits.
    public func flushForTermination() {
        let running = Array(copiers.values)
        stopAll(reason: nil)
        for copier in running { copier.waitUntilDone() }
    }

    // MARK: Conflicts

    /// Back to back on another channel: when everything in the way is a recording whose
    /// window ends where this one begins, wait for that moment, end those recordings exactly
    /// then and take over their connection, without tuning in early and without asking.
    private func handOver(to id: UUID) async {
        guard let host, let recording = recordings.first(where: { $0.id == id }) else { return }
        let blockers = host.tuners.blockers(for: recording.channelId, as: .recording(id))
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
        guard let host else { return false }
        let blockers = host.tuners.blockers(for: recording.channelId, as: .recording(recording.id))
        guard !blockers.isEmpty else { return true }
        let blockingRecordings = recordings.filter { r in
            r.status == .recording && blockers.contains { $0.owners.contains(.recording(r.id)) }
        }
        let playerBlocks = blockers.contains { $0.owners.contains(.player) }

        let message: String
        let confirm: String
        if let other = blockingRecordings.first {
            message = String(localized: "“\(other.title)” is being recorded on \(other.channelName). Your account allows only \(host.tuners.limit) stream(s) at a time.", bundle: .module)
            confirm = String(localized: "Stop “\(other.title)” and Record", bundle: .module)
        } else {
            message = String(localized: "To record, Fernsy switches to \(recording.channelName), because your account allows only \(host.tuners.limit) stream(s) at a time.", bundle: .module)
            confirm = String(localized: "Switch and Record", bundle: .module)
        }
        let accepted = await host.ask(
            title: String(localized: "Recording “\(recording.title)” Is Starting", bundle: .module),
            message: message + "\n\n" + String(localized: "Without an answer, the recording starts in one minute.", bundle: .module),
            confirm: confirm, cancel: String(localized: "Skip Recording", bundle: .module), timeout: 60, timeoutAnswer: true)
        guard accepted else { return false }
        for other in blockingRecordings { finish(other.id, error: nil) }
        if playerBlocks { host.playForRecording(recording.channelId) }
        return true
    }

    // MARK: Keeping the device awake

    /// Keeps the device awake while a recording runs or, by the policy, the next one starts
    /// soon. The reason names that recording (on the Mac, `pmset -g assertions` explains it).
    private func updateActivity() {
        let policy = keepAwakePolicy()
        let reason: String?
        if policy == .never {
            reason = nil
        } else if let running = recordings.first(where: { $0.status == .recording }) {
            reason = "Recording: \(running.title)"
        } else if case .ahead(let hours) = policy {
            let limit = hours.map { Date().addingTimeInterval(Double($0) * 3600) } ?? Date.distantFuture
            let next = recordings.filter { $0.status == .scheduled && $0.recordStart < limit }.min { $0.recordStart < $1.recordStart }
            reason = next.map { "Recording scheduled: \($0.title) at \($0.recordStart.formatted(date: .abbreviated, time: .shortened))" }
        } else {
            reason = nil
        }
        guard reason != activityReason else { return }
        activityReason = reason
        host?.keepAwake(reason: reason)
    }

    // MARK: Files

    private static func fileName(for recording: Recording, in folder: URL) -> String {
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
