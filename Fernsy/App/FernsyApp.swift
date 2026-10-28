import FernsyCore
import FernsyPlayer
import SwiftUI

@main
struct FernsyApp: App {
    @StateObject private var app = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage(MenuBarSupport.enabledKey) private var showsMenuBarItem = true

    var body: some Scene {
        WindowGroup("Fernsy", id: "library") {
            Group {
                // icloud-auto-signin: the logins in iCloud are tried first; the screen stays
                // until the channels are loaded, then fades into the library.
                if app.signingInFromICloud {
                    ICloudSignInView().transition(.opacity)
                } else if app.credentials == nil && !app.hasJellyfin {
                    LoginView().transition(.opacity)
                } else {
                    LibraryView().transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: app.signingInFromICloud)
            .environmentObject(app)
            .environmentObject(app.recorder)
            .environmentObject(app.jellyfin)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            LogCommands()
            #if DIRECT_DISTRIBUTION
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: app.updater)
            }
            #endif
            CommandGroup(after: .toolbar) {
                Button("Refresh Catalog") {
                    Task { await app.loadCatalog(forceRefresh: true) }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(app.credentials == nil || app.isLoading)
            }
        }

        // A single player window: Xtream accounts usually allow one stream at a time.
        Window("Playback", id: "player") {
            PlayerScreen()
                .environmentObject(app)
                .environmentObject(app.recorder)
                .environmentObject(app.jellyfin)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Log", id: "log") {
            LogView()
        }
        .defaultSize(width: 980, height: 560)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environmentObject(app)
                .environmentObject(app.recorder)
                .environmentObject(app.jellyfin)
        }

        // Read-only: MenuBarExtra writes the binding back on every update, which with
        // @AppStorage turns into an endless update loop.
        MenuBarExtra(isInserted: Binding(get: { showsMenuBarItem }, set: { _ in })) {
            MenuBarContent()
                .environmentObject(app)
                .environmentObject(app.recorder)
        } label: {
            MenuBarLabel(recorder: app.recorder)
        }
    }
}

/// Asks before quitting while recordings run or are planned: they only happen while Fernsy is open.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var app: AppModel?
    private var observers: [NSObjectProtocol] = []

    @MainActor
    func applicationWillFinishLaunching(_ notification: Notification) {
        LoginItem.detectLaunch()
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [MenuBarSupport.enabledKey: true])
        let info = Bundle.main.infoDictionary
        AppLog.info(.app, "Fernsy \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?")) started, macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { MenuBarSupport.windowWillClose(window) }
        })
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { MenuBarSupport.windowDidOpen(window) }
        })
        if LoginItem.launchedAtLogin { MenuBarSupport.startWithoutWindow() }
        #if DEBUG
        // IPTV_TESTCLOSE=<s>: close every window after that many seconds (menu bar mode).
        if let delay = ProcessInfo.processInfo.environment["IPTV_TESTCLOSE"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                for window in NSApp.windows {
                    debugLog("[test] window \(window.identifier?.rawValue ?? "-") visible=\(window.isVisible) main=\(window.canBecomeMain)")
                    if window.isVisible && window.canBecomeMain { window.close() }
                }
            }
        }
        #endif
    }

    /// Closing the last window keeps Fernsy running: recordings happen in the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let recorder = Self.app?.recorder, recorder.hasActiveOrUpcoming else { return .terminateNow }
        let running = recorder.recordings.contains { $0.status == .recording }
        let alert = NSAlert()
        alert.messageText = running ? String(localized: "A Recording Is in Progress") : String(localized: "Recordings Are Scheduled")
        alert.informativeText = running
            ? String(localized: "If you quit Fernsy, the recording ends now. What has been recorded so far is kept.")
            : String(localized: "Recordings only run while Fernsy is open. You can close all windows but keep Fernsy running.")
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        recorder.flushForTermination()
        return .terminateNow
    }
}
