import Combine
import Foundation

/// "IPTV only with VPN" for the views and models (vpn-guard): the setting and whether a VPN is
/// seen, kept current on the main actor. `ProviderGate` decides at each request; this follows it
/// for what is shown, and tells the models when the provider can be reached again.
@MainActor
public final class VPNGuardState: ObservableObject {
    public static let shared = VPNGuardState(gate: .shared)

    @Published public private(set) var isEnabled: Bool
    /// A VPN carries the device's internet traffic. Current while the setting is on or a view
    /// that shows it is open (`watch`).
    @Published public private(set) var isVPNConnected: Bool
    /// The setting is on and no VPN is connected: nothing goes to the IPTV provider.
    public var isBlocking: Bool { isEnabled && !isVPNConnected }
    /// The provider can be reached again after `isBlocking`: load what was refused.
    public let reopened = PassthroughSubject<Void, Never>()

    private let gate: ProviderGate
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var watchers = 0

    public init(gate: ProviderGate, interval: TimeInterval = 2) {
        self.gate = gate
        isEnabled = gate.isEnabled
        isVPNConnected = gate.isVPNConnected
        observer = NotificationCenter.default.addObserver(forName: ProviderGate.didChange, object: gate, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        // The network path does not report every VPN change (and not at once): look regularly
        // while the answer matters.
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    public func setEnabled(_ on: Bool) {
        gate.isEnabled = on
        update()
    }

    /// A view that shows whether a VPN is seen is on screen (also while the setting is off).
    public func watch(_ on: Bool) {
        watchers += on ? 1 : -1
        if on { update() }
    }

    /// Looks again now: after a change of the network path, or of the debug switch.
    public func update() {
        let wasBlocking = isBlocking
        let enabled = gate.isEnabled
        if enabled != isEnabled { isEnabled = enabled }
        if enabled || watchers > 0 {
            let connected = gate.isVPNConnected
            if connected != isVPNConnected { isVPNConnected = connected }
        }
        if wasBlocking && !isBlocking { reopened.send() }
    }
}
