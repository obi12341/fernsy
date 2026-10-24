import AppKit
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

    var recordStart: Date { start.addingTimeInterval(-padBefore) }
    var recordEnd: Date { end.addingTimeInterval(padAfter) }

    var isUpcomingOrRunning: Bool { status == .scheduled || status == .recording }

    func matches(channelId: Int, entry: EPGEntry) -> Bool {
        self.channelId == channelId && abs(start.timeIntervalSince(entry.start)) < 60 && title == entry.title
    }
}

extension Recording {
    private enum CodingKeys: String, CodingKey {
        case id, channelId, channelName, title, description, start, end, padBefore, padAfter
        case followsPaddingSettings, status, fileName, error, bytes
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
    private var starting: Set<UUID> = []
    private var timer: Timer?
    private var activity: NSObjectProtocol?

    /// Connect this early, so the recording has data from its first second.
    static let tuneAhead: TimeInterval = 20
    static let padBeforeKey = "recording.padBefore"
    static let padAfterKey = "recording.padAfter"

    private var defaultsObserver: NSObjectProtocol?
    private var appliedPadding: (before: TimeInterval, after: TimeInterval) = (0, 0)

    init() {
        UserDefaults.standard.register(defaults: [Self.padBeforeKey: 10, Self.padAfterKey: 10])
        appliedPadding = (padBefore, padAfter)
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
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
        #if DEBUG
        debugLog("[recording] padding now \(Int(before / 60))/\(Int(after / 60)) min for scheduled recordings")
        #endif
        save()
        tick()
    }

    /// ~/Movies/Fernsy (the real one, not the sandbox container's).
    static var folder: URL {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("Movies/Fernsy", isDirectory: true)
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
                    if r.fileName == nil { r.error = String(localized: "Keine Daten vom Sender") }
                }
                return r
            }
        }
        #if DEBUG
        debugLog("[recording] \(recordings.count) recordings loaded for this account")
        #endif
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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

    /// Plans a show (running or future). Returns a warning when it overlaps another recording
    /// on an account without a free connection.
    @discardableResult
    func schedule(_ entry: EPGEntry, on channel: LiveChannel, padding: (before: TimeInterval, after: TimeInterval)? = nil) -> String? {
        if let existing = recording(channelId: channel.id, entry: entry), existing.isUpcomingOrRunning { return nil }
        let recording = Recording(id: UUID(), channelId: channel.id, channelName: channel.name, title: entry.title,
                                  description: entry.description, start: entry.start, end: entry.end,
                                  padBefore: padding?.before ?? padBefore, padAfter: padding?.after ?? padAfter,
                                  followsPaddingSettings: padding == nil, status: .scheduled)
        recordings.append(recording)
        save()
        tick()
        return overlapWarning(for: recording)
    }

    /// Player: records the show that is on now (from its start, as far as the timeshift
    /// buffer reaches back), or the next two hours without programme data.
    func recordNow(_ channel: LiveChannel, entry: EPGEntry?) {
        if let entry {
            schedule(entry, on: channel)
        } else {
            let now = Date()
            let recording = Recording(id: UUID(), channelId: channel.id, channelName: channel.name,
                                      title: String(localized: "Aufnahme \(now.formatted(date: .abbreviated, time: .shortened))"),
                                      description: "", start: now, end: now.addingTimeInterval(2 * 3600),
                                      padBefore: 0, padAfter: 0, followsPaddingSettings: false, status: .scheduled)
            recordings.append(recording)
            save()
            tick()
        }
    }

    /// Stops a running recording now (keeping what was recorded) or drops a scheduled one.
    func stop(_ id: UUID) {
        guard let recording = recordings.first(where: { $0.id == id }) else { return }
        switch recording.status {
        case .recording: finish(id, error: nil)
        case .scheduled: recordings.removeAll { $0.id == id }; save()
        default: break
        }
    }

    /// Removes a recording from the list and moves its file to the trash.
    func delete(_ id: UUID) {
        guard let recording = recordings.first(where: { $0.id == id }) else { return }
        if recording.status == .recording { finish(id, error: nil) }
        if let url = fileURL(recording) { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        recordings.removeAll { $0.id == id }
        save()
    }

    func unschedule(channelId: Int, entry: EPGEntry) {
        guard let recording = recording(channelId: channelId, entry: entry) else { return }
        stop(recording.id)
    }

    private func overlapWarning(for recording: Recording) -> String? {
        guard let app else { return nil }
        let limit = app.tuners.limit
        let overlapping = recordings.filter {
            $0.id != recording.id && $0.isUpcomingOrRunning && $0.channelId != recording.channelId
                && $0.recordStart < recording.recordEnd && recording.recordStart < $0.recordEnd
        }
        guard overlapping.count >= limit, let other = overlapping.first else { return nil }
        return String(localized: "„\(recording.title)“ überschneidet sich mit der Aufnahme „\(other.title)“. Dein Zugang erlaubt \(limit) Stream(s) gleichzeitig – Fernsy fragt beim Start nach, welche Aufnahme laufen soll.")
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
                    if case .failed(let message) = tuner.state { reason = message } else { reason = String(localized: "Verbindung verloren") }
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
                update(recording.id) { $0.fileName = name }
                #if DEBUG
                debugLog("[recording] started \(recording.title) on \(recording.channelName) → \(name)")
                #endif
            } catch {
                finish(recording.id, error: error.localizedDescription)
            }
        }
    }

    /// Started (status `.recording`) but not writing yet, because no data has arrived.
    private func isWaiting(_ id: UUID) -> Bool {
        recordings.first { $0.id == id }?.status == .recording && copiers[id] == nil
    }

    private func finish(_ id: UUID, error: String?) {
        guard let recording = recordings.first(where: { $0.id == id }) else { return }
        let tuner = app?.tuners.tuner(recording.channelId)
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
        let error = recording.fileName == nil ? error ?? String(localized: "Keine Daten vom Sender") : error
        update(id) {
            $0.status = error == nil ? .done : .failed
            $0.error = error
            // A recording stopped early ends now.
            if Date() < $0.recordEnd { $0.end = max($0.start, Date()); $0.padAfter = 0 }
        }
        app?.tuners.release(recording.channelId, owner: .recording(id))
        #if DEBUG
        debugLog("[recording] finished \(recording.title)\(error.map { ": \($0)" } ?? "")")
        #endif
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
            message = String(localized: "Gerade wird „\(other.title)“ auf \(other.channelName) aufgenommen. Dein Zugang erlaubt nur \(app.tuners.limit) Stream(s) gleichzeitig.")
            confirm = String(localized: "„\(other.title)“ beenden und aufnehmen")
        } else {
            message = String(localized: "Für die Aufnahme schaltet Fernsy auf \(recording.channelName) um, weil dein Zugang nur \(app.tuners.limit) Stream(s) gleichzeitig erlaubt.")
            confirm = String(localized: "Umschalten und aufnehmen")
        }
        let accepted = await Prompt.ask(
            title: String(localized: "Aufnahme „\(recording.title)“ beginnt"),
            message: message + "\n\n" + String(localized: "Ohne Antwort startet die Aufnahme in einer Minute."),
            confirm: confirm, cancel: String(localized: "Aufnahme auslassen"), timeout: 60, timeoutAnswer: true)
        guard accepted else { return false }
        for other in blockingRecordings { finish(other.id, error: nil) }
        if playerBlocks, let channel = app.channel(recording.channelId) {
            app.play(channel, force: true)
        }
        return true
    }

    // MARK: Keeping the Mac awake

    private func updateActivity() {
        let soon = Date().addingTimeInterval(3600)
        let needed = recordings.contains { $0.status == .recording || ($0.status == .scheduled && $0.recordStart < soon) }
        if needed && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
                                                             reason: "Recording TV")
        } else if !needed, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
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
        NSApp.activate()
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
