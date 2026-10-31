import AppKit
import FernsyCore
import SwiftUI

/// Opens the player window from outside a view (an MCP `play` while no library window is
/// open, e.g. Fernsy runs in the menu bar). Views hand over their `openWindow`.
@MainActor
enum PlayerWindow {
    static var openWindow: OpenWindowAction?
    /// From the menu bar item, which outlives the windows (see `MenuBarLabel`).
    static var menuBarOpenWindow: OpenWindowAction?

    private static func open(_ id: String) {
        (menuBarOpenWindow ?? openWindow)?(id: id)
    }

    private static var window: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("player") == true }
    }

    /// A player window opened by `show` comes to the front once it appears (`appeared()`).
    private static var pendingFront = false

    /// Playback started from outside Fernsy (MCP, Siri): the player comes in front of every
    /// window without activating Fernsy, so the user's app keeps keyboard focus. A new window of
    /// a background app would otherwise open behind the active app's windows.
    static func show(_ app: AppModel) {
        guard !app.isPictureInPictureActive else { return }
        NSApp.setActivationPolicy(.regular)
        if let window, window.isVisible || window.isMiniaturized {
            if window.isMiniaturized { window.deminiaturize(nil) }
            orderFront()
            AppLog.detail(.app, "player window brought to the front")
            return
        }
        pendingFront = true
        open("player")
    }

    /// Called by the player when its window appears.
    static func appeared() {
        guard pendingFront else { return }
        pendingFront = false
        orderFront()
        AppLog.detail(.app, "new player window brought to the front")
    }

    /// SwiftUI orders a new window in after onAppear, and starting playback reorders an existing
    /// one; a single call is undone by that, so it repeats briefly.
    private static func orderFront() {
        for delay in [0, 0.15, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { AppActivation.orderFrontRegardless(window) }
        }
    }

    static func close() {
        if let window, window.isVisible { window.close() }
    }

    /// Brings the library window to the front, or opens one (Fernsy may run in the menu bar).
    static func showLibrary() {
        NSApp.setActivationPolicy(.regular)
        AppActivation.activate()
        if let hidden = LibraryWindows.takeHidden() {
            hidden.makeKeyAndOrderFront(nil)
            AppLog.detail(.app, "hidden library window brought to the front")
        } else if let library = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("library") == true && $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized) }) {
            library.deminiaturize(nil)
            library.makeKeyAndOrderFront(nil)
            AppLog.detail(.app, "library window brought to the front")
        } else {
            AppLog.detail(.app, "opening a library window (menu bar action: \(menuBarOpenWindow != nil))")
            open("library")
        }
    }
}
