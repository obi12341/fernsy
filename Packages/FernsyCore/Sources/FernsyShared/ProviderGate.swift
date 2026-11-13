import Foundation

public enum ProviderGateError: LocalizedError, Sendable {
    /// "IPTV only with VPN" is on and the device's traffic does not leave through a VPN.
    case vpnRequired

    public var errorDescription: String? {
        String(localized: "No VPN connection. Fernsy contacts your IPTV provider only through a VPN.", bundle: .module)
    }
}

/// The setting "IPTV only with VPN" (vpn-guard): while it is on and no VPN carries the device's
/// internet traffic, nothing is sent to the IPTV provider. Checked where connections to the
/// provider are made (`XtreamClient`, provider streams, artwork downloads); Jellyfin, Fernsy
/// Cloud and the Fernsy Server do not ask it. The probe runs at each check, so the answer is
/// the kernel's at that moment. Always open on Linux (Fernsy Server).
public final class ProviderGate: @unchecked Sendable {
    public static let shared = ProviderGate(forced: forcedByEnvironment)

    /// Per device: not among the keys synced through iCloud (a device behind a VPN router cannot
    /// see that VPN and keeps the setting off).
    public static let enabledKey = "vpnGuardEnabled"
    /// Posted on the main queue, after the check that noticed it returned, when the setting, the
    /// VPN or with them `isOpen` changed. Never from inside the check: streams ask while they
    /// hold their own lock, and an observer on the main thread may be waiting for that lock.
    public static let didChange = Notification.Name("FernsyProviderGateDidChange")

    /// `IPTV_TESTVPNGUARD=1` (debug builds): the setting is on for this run, without storing it.
    private static var forcedByEnvironment: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["IPTV_TESTVPNGUARD"] == "1"
        #else
        false
        #endif
    }

    private let defaults: UserDefaults
    private let forced: Bool
    private let probe: () -> VPNProbe.Routes
    private let lock = NSLock()
    private var last: (enabled: Bool, connected: Bool)?
    private var ownHosts: Set<String> = []

    public init(defaults: UserDefaults = .standard, forced: Bool = false, probe: @escaping () -> VPNProbe.Routes = { VPNProbe.current() }) {
        self.defaults = defaults
        self.forced = forced
        self.probe = probe
    }

    public var isEnabled: Bool {
        get {
            #if canImport(Darwin)
            forced || defaults.bool(forKey: Self.enabledKey)
            #else
            false
            #endif
        }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            refresh()
        }
    }

    /// A VPN carries the device's internet traffic now.
    public var isVPNConnected: Bool { evaluate().connected }

    /// Requests to the provider may be sent now.
    public var isOpen: Bool {
        guard isEnabled else { return true }
        return evaluate().connected
    }

    /// Throws `ProviderGateError.vpnRequired` while the gate is closed. `what` names the refused
    /// request in the log (no addresses: the log must not hold the provider's).
    public func check(_ what: String) throws {
        guard isEnabled else { return }
        let state = evaluate()
        guard !state.connected else { return }
        AppLog.warning(.network, "vpn guard: \(what) refused, no VPN (\(state.routes))")
        throw ProviderGateError.vpnRequired
    }

    /// The host of the user's own server (Jellyfin), whose artwork is not the provider's; nil
    /// when signed out.
    public func setOwnHost(_ host: String?) {
        lock.lock()
        ownHosts = host.map { [$0.lowercased()] } ?? []
        lock.unlock()
    }

    /// Artwork may be downloaded from `url` now. Logos and posters come from wherever the
    /// provider's catalog points, so every host but the user's own server is the provider's.
    public func allowsDownload(from url: URL) -> Bool {
        if url.isFileURL { return true }
        lock.lock()
        let own = url.host.map { ownHosts.contains($0.lowercased()) } ?? false
        lock.unlock()
        return own || isOpen
    }

    /// Looks again and tells the observers if something changed: after a change of the network
    /// path or of the setting.
    public func refresh() {
        _ = evaluate()
    }

    private func evaluate() -> (connected: Bool, routes: VPNProbe.Routes) {
        let routes = probe()
        let now = (enabled: isEnabled, connected: routes.usesTunnel)
        lock.lock()
        let before = last
        last = now
        lock.unlock()
        if let before, before == now { return (now.connected, routes) }
        if before != nil || now.enabled {
            let text = "vpn guard \(now.enabled ? "on" : "off"): \(now.connected ? "VPN connected" : "no VPN") (\(routes))"
            if now.enabled { AppLog.info(.network, text) } else { AppLog.detail(.network, text) }
        }
        if before != nil {
            DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: self) }
        }
        return (now.connected, routes)
    }
}
