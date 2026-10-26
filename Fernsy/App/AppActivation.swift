import AppKit

/// Bringing Fernsy to the front. Debug builds stay behind the app the user is using unless
/// `IPTV_ACTIVATE=1`, so a test run never takes the focus or covers a full-screen player.
enum AppActivation {
    static let isQuiet: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["IPTV_ACTIVATE"] != "1"
        #else
        return false
        #endif
    }()

    static func activate() {
        guard !isQuiet else { return }
        NSApp.activate()
    }

    /// In front of every window, without activating Fernsy.
    static func orderFrontRegardless(_ window: NSWindow?) {
        guard !isQuiet else { return }
        window?.orderFrontRegardless()
    }
}
