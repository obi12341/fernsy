import FernsyCore
import FernsyPlayer
import Foundation
import UIKit

/// A yes/no question of the recorder (stream limit), answered in an alert or by its timeout.
struct RecorderQuestion: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirm: String
    let cancel: String
    let answer: (Bool) -> Void
}

/// Recordings on Apple TV (designs C and D of tvos-live): files and list in Caches, which tvOS
/// may purge; only while the app is open, keeping the Apple TV awake meanwhile.
extension TVModel: RecorderHost {
    func liveURL(_ channelId: Int) -> URL? { client?.liveURL(channelId) }

    func playForRecording(_ channelId: Int) {
        if let channel = channels.first(where: { $0.id == channelId }) { play(channel) }
    }

    func ask(title: String, message: String, confirm: String, cancel: String, timeout: TimeInterval, timeoutAnswer: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            var answered = false
            let finish: (Bool) -> Void = { [weak self] value in
                guard !answered else { return }
                answered = true
                self?.question = nil
                continuation.resume(returning: value)
            }
            question = RecorderQuestion(title: title, message: message, confirm: confirm, cancel: cancel, answer: finish)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                finish(timeoutAnswer)
            }
        }
    }

    /// Caches/Recordings/<account>: the list and the files together, so they go together.
    static func recordingsDirectory(accountKey: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings/\(accountKey)", isDirectory: true)
    }

    func recordingsStore(accountKey: String) -> URL { Self.recordingsDirectory(accountKey: accountKey) }

    var recordingsFolder: URL {
        Self.recordingsDirectory(accountKey: credentials?.accountKey ?? "none")
    }

    func removeRecordingFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// The Apple TV must not sleep during a recording; tvOS' idle timer would send it to sleep.
    func keepAwake(reason: String?) {
        UIApplication.shared.isIdleTimerDisabled = reason != nil
        AppLog.info(.recordings, reason.map { "keeping the Apple TV awake: \($0)" } ?? "the Apple TV may sleep again")
    }

    /// Below 2 GB free, a recording does not start (design D).
    func recordingRefusal() -> String? {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let free = values.volumeAvailableCapacity else { return nil }
        #if DEBUG
        if ProcessInfo.processInfo.environment["IPTV_TESTNOSPACE"] == "1" { return Self.noSpaceMessage }
        #endif
        return free < 2_000_000_000 ? Self.noSpaceMessage : nil
    }

    private static var noSpaceMessage: String {
        String(localized: "Not enough free space on the Apple TV (at least 2 GB needed).")
    }

    var dropsMissingRecordings: Bool { true }

    /// tvOS suspends the app soon after it leaves the screen: running recordings end now and
    /// keep what they got (design C).
    func appWillLeave() {
        guard recorder.recordings.contains(where: { $0.status == .recording }) else { return }
        AppLog.info(.recordings, "the app is left: running recordings stop")
        recorder.stopAll(reason: String(localized: "Incomplete: Fernsy was left during the recording"))
    }

    // MARK: Actions

    func activeRecording(on channel: LiveChannel) -> Recording? { recorder.active(on: channel.id) }

    /// Records the show on now (or the next two hours without programme data); refusals and
    /// shortened padding come back as a message.
    @discardableResult
    func recordNow(_ channel: LiveChannel) -> String? {
        message(recorder.recordNow(channel, entry: currentShow(on: channel)))
    }

    @discardableResult
    func schedule(_ show: EPGEntry, on channel: LiveChannel) -> String? {
        message(recorder.schedule(show, on: channel))
    }

    func isScheduled(_ show: EPGEntry, on channel: LiveChannel) -> Bool {
        recorder.recording(channelId: channel.id, entry: show)?.isUpcomingOrRunning == true
    }

    private func message(_ result: Recorder.PlanResult) -> String? {
        switch result {
        case .planned(let notice): notice
        case .refused(let message): message
        }
    }

    #if DEBUG
    /// IPTV_TESTRECORD=<channel>:<starts in s>:<seconds>[:<before min>:<after min>],…, as on the Mac.
    func testRecord() {
        guard let list = ProcessInfo.processInfo.environment["IPTV_TESTRECORD"] else { return }
        let specs = list.split(separator: ",").map { $0.split(separator: ":").compactMap { Double($0) } }.filter { $0.count == 3 || $0.count == 5 }
        let now = Date()
        for (n, spec) in specs.enumerated() {
            guard let channel = channels.first(where: { $0.id == Int(spec[0]) }) else { continue }
            let start = now.addingTimeInterval(spec[1])
            let entry = EPGEntry(id: "test\(n)", title: "Test \(n + 1) \(Int(spec[0]))", description: "", start: start, end: start.addingTimeInterval(spec[2]))
            recorder.schedule(entry, on: channel, padding: spec.count == 5 ? (spec[3] * 60, spec[4] * 60) : (0, 0))
        }
    }
    #endif
}
