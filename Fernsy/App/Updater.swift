#if DIRECT_DISTRIBUTION
import Combine
import Foundation
import Sparkle
import SwiftUI

/// Updates of the directly distributed build (DMG) through Sparkle. The App Store build has no
/// updater: this file only exists in the "Fernsy Direct" target's compilation.
///
/// The feed is the newest release's appcast, or the nightly's when the user opted in. An
/// update never relaunches Fernsy while a recording runs or starts within half an hour;
/// it waits until then (or installs when the user quits).
@MainActor
final class Updater: NSObject, ObservableObject {
    nonisolated static let nightlyKey = "updates.nightly"
    nonisolated static let releaseFeed = "https://github.com/obi12341/fernsy/releases/latest/download/appcast.xml"
    nonisolated static let nightlyFeed = "https://github.com/obi12341/fernsy/releases/download/nightly/appcast.xml"
    /// Recordings starting this soon also hold an update back.
    static let recordingMargin: TimeInterval = 30 * 60

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastCheck: Date?

    private weak var recorder: Recorder?
    private var controller: SPUStandardUpdaterController!
    private var heldInstall: (() -> Void)?
    private var holdTimer: Timer?
    private var observations: [AnyCancellable] = []

    var updater: SPUUpdater { controller.updater }

    /// Nightlies carry the version "nightly-<date>"; releases a number.
    nonisolated static var isNightlyBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "").hasPrefix("nightly-")
    }

    init(recorder: Recorder) {
        self.recorder = recorder
        super.init()
        // A nightly follows the nightly feed unless the user chose otherwise, so a nightly
        // downloaded by hand keeps getting nightlies; releases follow the release feed.
        UserDefaults.standard.register(defaults: [Self.nightlyKey: Self.isNightlyBuild])
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }.store(in: &observations)
        updater.publisher(for: \.lastUpdateCheckDate).receive(on: RunLoop.main)
            .sink { [weak self] in self?.lastCheck = $0 }.store(in: &observations)
        #if DEBUG
        if ProcessInfo.processInfo.environment["IPTV_TESTUPDATEHOLD"] != nil {
            // IPTV_TESTUPDATEHOLD=1: logs every 10 s whether an update would wait for recordings.
            Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    AppLog.info(.app, "[test] update hold: \(self.recordingDue ? "waits for recordings" : "would install")")
                }
            }
        }
        // Debug builds share the sandbox container (and Sparkle's settings) with the installed
        // Fernsy: Sparkle only runs with an explicit test feed (IPTV_UPDATEFEED=<url>).
        guard Self.debugFeed != nil else { return }
        #endif
        // Without the public key Sparkle cannot verify anything and would report errors.
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else {
            AppLog.error(.app, "updates are off: this build has no SUPublicEDKey")
            return
        }
        controller.startUpdater()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var checksAutomatically: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { objectWillChange.send(); updater.automaticallyChecksForUpdates = newValue }
    }

    /// A running recording, or one starting within `recordingMargin`, keeps Fernsy from relaunching.
    var recordingDue: Bool {
        let soon = Date().addingTimeInterval(Self.recordingMargin)
        return recorder?.recordings.contains {
            $0.status == .recording || ($0.status == .scheduled && $0.recordStart < soon)
        } ?? false
    }

    nonisolated private static var debugFeed: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["IPTV_UPDATEFEED"]
        #else
        nil
        #endif
    }

    private func holdUntilNoRecording(_ install: @escaping () -> Void) {
        heldInstall = install
        holdTimer?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseIfFree() }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    private func releaseIfFree() {
        guard !recordingDue, let install = heldInstall else { return }
        holdTimer?.invalidate()
        holdTimer = nil
        heldInstall = nil
        AppLog.info(.app, "no recording due any more, installing the update")
        install()
    }
}

/// "Nach Updates suchen …" in the Fernsy menu.
struct CheckForUpdatesButton: View {
    @ObservedObject var updater: Updater

    var body: some View {
        Button("Nach Updates suchen …") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}

/// Settings › Konten: automatic checks, the nightly channel, last check.
struct UpdateSettingsSection: View {
    @ObservedObject var updater: Updater
    @AppStorage(Updater.nightlyKey) private var nightly = false

    var body: some View {
        Section {
            Toggle("Automatisch nach Updates suchen", isOn: Binding(
                get: { updater.checksAutomatically }, set: { updater.checksAutomatically = $0 }))
            Toggle("Nightly-Builds erhalten", isOn: $nightly)
            HStack {
                if let last = updater.lastCheck {
                    Text("Zuletzt gesucht: \(last.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Jetzt suchen") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("Nightly-Builds sind tägliche Testversionen mit den neuesten Änderungen. Sie können Fehler enthalten. Updates werden nie während einer Aufnahme installiert.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension Updater: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        if let debug = Self.debugFeed { return debug }
        return UserDefaults.standard.bool(forKey: Self.nightlyKey) ? Self.nightlyFeed : Self.releaseFeed
    }

    nonisolated func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                             untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        MainActor.assumeIsolated {
            guard recordingDue else { return false }
            AppLog.info(.app, "update \(item.displayVersionString) (\(item.versionString)) waits for the recordings")
            Prompt.inform(title: String(localized: "Update nach der Aufnahme"),
                          message: String(localized: "Fernsy installiert das Update, sobald keine Aufnahme mehr läuft oder in der nächsten halben Stunde beginnt. Beim Beenden von Fernsy wird es sofort installiert."))
            holdUntilNoRecording(installHandler)
            return true
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        guard let error else { return }
        let nsError = error as NSError
        // "No update" is reported as an error too; only real failures go to the log.
        guard nsError.domain != SUSparkleErrorDomain || nsError.code != Int(SUError.noUpdateError.rawValue) else { return }
        MainActor.assumeIsolated { AppLog.error(.app, "update check failed: \(error.localizedDescription)") }
    }
}
#endif
