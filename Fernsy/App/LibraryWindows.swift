import AppKit
import FernsyCore

/// Library windows hidden while the player is in full screen. With no Fernsy window left on the
/// desktop, activating Fernsy (⌘-Tab, Dock) switches to the player's full-screen Space instead of
/// showing the library there.
@MainActor
enum LibraryWindows {
    private struct Hidden { weak var window: NSWindow? }
    private static var hidden: [Hidden] = []

    private static func isLibrary(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix("library") == true
    }

    /// Hides the visible library windows (minimized ones are not on the desktop anyway).
    static func hideForFullScreen() {
        let windows = NSApp.orderedWindows.filter { isLibrary($0) && $0.isVisible && !$0.isMiniaturized }
        guard !windows.isEmpty else { return }
        hidden += windows.map { Hidden(window: $0) }
        windows.forEach { $0.orderOut(nil) }
        AppLog.detail(.app, "library hidden while the player is in full screen (\(windows.count))")
    }

    /// Brings the hidden windows back in their order, behind the player so it keeps the focus.
    static func restore(below player: NSWindow?) {
        let windows = hidden.compactMap(\.window)
        hidden = []
        guard !windows.isEmpty else { return }
        // Backmost first: each one goes directly below the player, pushing the earlier ones down.
        for window in windows.reversed() {
            if let player, player.isVisible {
                window.order(.below, relativeTo: player.windowNumber)
            } else {
                window.orderFront(nil)
            }
        }
        AppLog.detail(.app, "library shown again (\(windows.count))")
    }

    /// A hidden library window for someone asking for the library; it is no longer hidden.
    static func takeHidden() -> NSWindow? {
        guard let window = hidden.compactMap(\.window).first else { return nil }
        hidden.removeAll { $0.window == nil || $0.window === window }
        return window
    }
}
