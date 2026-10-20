import SwiftUI

/// Menu bar item: Fernsy keeps running there (for recordings) when all windows are closed.
struct MenuBarContent: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let running = recorder.recordings.filter { $0.status == .recording }
        let next = recorder.recordings.filter { $0.status == .scheduled }.min { $0.start < $1.start }

        if running.isEmpty && next == nil {
            Text("Keine Aufnahmen geplant")
        }
        ForEach(running) { recording in
            Menu("● \(recording.title) – \(recording.channelName)") {
                Text("Bis \(recording.recordEnd.formatted(date: .omitted, time: .shortened))")
                Button("Aufnahme beenden") { recorder.stop(recording.id) }
            }
        }
        if let next {
            Text("Nächste: \(next.title) – \(Self.when(next.start))")
        }
        Divider()
        Button("Fernsy öffnen") { MenuBarSupport.showLibrary(openWindow) }
        Button("Aufnahmen anzeigen") {
            app.requestedSection = .recordings
            MenuBarSupport.showLibrary(openWindow)
        }
        Divider()
        Button("Fernsy beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private static func when(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return time }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " " + time
    }
}

struct MenuBarLabel: View {
    @ObservedObject var recorder: Recorder

    var body: some View {
        Image(systemName: recorder.recordings.contains { $0.status == .recording } ? "record.circle.fill" : "tv")
    }
}

/// Dock icon only while a window is open; without windows Fernsy lives in the menu bar.
@MainActor
enum MenuBarSupport {
    static let enabledKey = "menuBar.enabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Real windows (library, player, settings), not the menu bar's own panel.
    private static var openWindows: [NSWindow] {
        NSApp.windows.filter { $0.isVisible && $0.canBecomeMain && $0.styleMask.contains(.titled) }
    }

    static func windowWillClose(_ closing: NSWindow) {
        guard isEnabled, closing.canBecomeMain else { return }
        // After the close has gone through.
        DispatchQueue.main.async {
            if openWindows.filter({ $0 !== closing }).isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    static func windowDidOpen(_ window: NSWindow) {
        guard window.canBecomeMain, NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Brings the library window back, or opens a new one when it was closed.
    static func showLibrary(_ openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if let existing = NSApp.windows.first(where: {
            $0.identifier?.rawValue.hasPrefix("library") == true && $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized)
        }) {
            existing.deminiaturize(nil)
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "library")
        }
    }
}
