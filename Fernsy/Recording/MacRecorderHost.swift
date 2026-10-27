import AppKit
import FernsyCore
import FernsyPlayer
import Foundation

/// The Mac's side of the recorder (`RecorderHost`): ~/Movies/Fernsy, the account folder,
/// questions as sheets, the trash and keeping the Mac awake.
extension Recorder {
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

    /// Hours before a scheduled recording from which the Mac is kept from idle sleep:
    /// 0 keeps it awake while any recording is scheduled, -1 never (not even while recording).
    static let keepAwakeHoursKey = "recording.keepAwakeHours"
    static let keepAwakeChoices = [-1, 1, 3, 6, 12, 24, 0]

    /// Call once before setting `keepAwakePolicy`: registering posts didChangeNotification, and
    /// the policy must not register while it is read.
    static func registerMacDefaults() {
        UserDefaults.standard.register(defaults: [keepAwakeHoursKey: 6])
    }

    /// The Mac's keep-awake setting as a policy; IPTV_AWAKEHOURS=<hours|0|off> (debug) replaces
    /// it for this run, in memory only.
    static func macKeepAwakePolicy() -> KeepAwakePolicy {
        var hours = UserDefaults.standard.integer(forKey: keepAwakeHoursKey)
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment["IPTV_AWAKEHOURS"] {
            hours = value == "off" ? -1 : Int(value) ?? hours
        }
        #endif
        return hours < 0 ? .never : .ahead(hours: hours == 0 ? nil : hours)
    }
}

extension AppModel: RecorderHost {
    func liveURL(_ channelId: Int) -> URL? { client?.liveURL(channelId) }

    func playForRecording(_ channelId: Int) {
        if let channel = channel(channelId) { play(channel, force: true) }
    }

    func ask(title: String, message: String, confirm: String, cancel: String, timeout: TimeInterval, timeoutAnswer: Bool) async -> Bool {
        await Prompt.ask(title: title, message: message, confirm: confirm, cancel: cancel, timeout: timeout, timeoutAnswer: timeoutAnswer)
    }

    func recordingsStore(accountKey: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fernsy/\(accountKey)", isDirectory: true)
    }

    var recordingsFolder: URL { Recorder.folder }

    func removeRecordingFile(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Holds an activity against idle sleep; its reason names the recording, so
    /// `pmset -g assertions` explains it.
    func keepAwake(reason: String?) {
        if let activity = recordingActivity {
            ProcessInfo.processInfo.endActivity(activity)
            recordingActivity = nil
        }
        if let reason {
            recordingActivity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .suddenTerminationDisabled], reason: reason)
            let span = if case .ahead(let hours?) = Recorder.macKeepAwakePolicy() { "\(hours) h" } else { "always" }
            AppLog.info(.recordings, "keeping the Mac awake (\(span)): \(reason)")
        } else {
            AppLog.info(.recordings, Recorder.macKeepAwakePolicy() == .never ? "keep-awake off" : "the Mac may sleep again")
        }
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
