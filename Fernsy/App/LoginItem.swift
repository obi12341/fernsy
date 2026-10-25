import AppKit
import ServiceManagement

/// "Beim Anmelden öffnen": Fernsy as a macOS login item (`SMAppService.mainApp`). macOS keeps the
/// state, so the user can also remove the item in System Settings › General › Login Items.
@MainActor
final class LoginItem: ObservableObject {
    enum Status { case enabled, requiresApproval, off }

    @Published private(set) var status: Status = .off

    /// macOS opened Fernsy as a login item at this launch (set in `applicationWillFinishLaunching`).
    static private(set) var launchedAtLogin = false

    init() { refresh() }

    func refresh() {
        #if DEBUG
        // Debug builds never register: a bundle in DerivedData would become a real login item.
        // IPTV_TESTLOGINITEM=<enabled|approval|off> fakes what macOS reports.
        switch ProcessInfo.processInfo.environment["IPTV_TESTLOGINITEM"] {
        case "enabled": status = .enabled
        case "approval": status = .requiresApproval
        default: break
        }
        #else
        switch SMAppService.mainApp.status {
        case .enabled: status = .enabled
        case .requiresApproval: status = .requiresApproval
        default: status = .off
        }
        #endif
    }

    func setEnabled(_ enabled: Bool) {
        #if DEBUG
        status = enabled ? .enabled : .off
        AppLog.info(.app, "login item \(enabled ? "on" : "off") (debug build, not registered)")
        #else
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            AppLog.info(.app, "login item \(enabled ? "registered" : "removed")")
        } catch {
            AppLog.error(.app, "login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
        refresh()
        #endif
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Reads the launch's Apple Event: macOS marks the open event of a login item.
    static func detectLaunch() {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        #if DEBUG
        // IPTV_TESTLOGINLAUNCH=1: start as if macOS opened Fernsy at login.
        if ProcessInfo.processInfo.environment["IPTV_TESTLOGINLAUNCH"] == "1" { launchedAtLogin = true }
        #endif
        if launchedAtLogin { AppLog.info(.app, "opened at login: starting without a window") }
    }
}
