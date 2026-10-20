import SwiftUI

@main
struct FernsyApp: App {
    @StateObject private var app = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage(MenuBarSupport.enabledKey) private var showsMenuBarItem = true

    var body: some Scene {
        WindowGroup("Fernsy", id: "library") {
            Group {
                if app.credentials == nil && !app.hasJellyfin {
                    LoginView()
                } else {
                    LibraryView()
                }
            }
            .environmentObject(app)
            .environmentObject(app.recorder)
            .environmentObject(app.jellyfin)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Katalog aktualisieren") {
                    Task { await app.loadCatalog(forceRefresh: true) }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(app.credentials == nil || app.isLoading)
            }
        }

        // A single player window: Xtream accounts usually allow one stream at a time.
        Window("Wiedergabe", id: "player") {
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [MenuBarSupport.enabledKey: true])
        #if DEBUG
        debugLog("[app] did finish launching")
        #endif
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { MenuBarSupport.windowWillClose(window) }
        })
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { MenuBarSupport.windowDidOpen(window) }
        })
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
        alert.messageText = running ? String(localized: "Eine Aufnahme läuft") : String(localized: "Aufnahmen sind geplant")
        alert.informativeText = running
            ? String(localized: "Wenn du Fernsy beendest, endet die Aufnahme jetzt. Das bisher Aufgenommene bleibt erhalten.")
            : String(localized: "Aufnahmen laufen nur, solange Fernsy geöffnet ist. Du kannst alle Fenster schließen, Fernsy aber geöffnet lassen.")
        alert.addButton(withTitle: String(localized: "Beenden"))
        alert.addButton(withTitle: String(localized: "Abbrechen"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        recorder.flushForTermination()
        return .terminateNow
    }
}
