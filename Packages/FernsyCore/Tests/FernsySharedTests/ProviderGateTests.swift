import Foundation
import Testing
@testable import FernsyShared

/// The setting "IPTV only with VPN" and what it lets through (vpn-guard 2.1, 2.2).
struct ProviderGateTests {
    final class Network: @unchecked Sendable {
        var vpn = false
        var asked = 0
    }

    private func gate(enabled: Bool, forced: Bool = false) throws -> (ProviderGate, Network, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "gate-\(UUID().uuidString)"))
        if enabled { defaults.set(true, forKey: ProviderGate.enabledKey) }
        let network = Network()
        let gate = ProviderGate(defaults: defaults, forced: forced) {
            network.asked += 1
            return VPNProbe.current(faked: network.vpn)
        }
        return (gate, network, defaults)
    }

    @Test func offByDefaultAndOpenWhateverTheProbeSays() throws {
        let (gate, network, _) = try gate(enabled: false)
        #expect(!gate.isEnabled)
        #expect(gate.isOpen)
        try gate.check("test")
        network.vpn = true
        #expect(gate.isOpen)
    }

    #if canImport(Darwin)
    @Test func onWithoutAVPNRefuses() throws {
        let (gate, _, _) = try gate(enabled: true)
        #expect(!gate.isOpen)
        #expect(!gate.isVPNConnected)
        #expect(throws: ProviderGateError.self) { try gate.check("test") }
    }

    @Test func onWithAVPNIsOpen() throws {
        let (gate, network, _) = try gate(enabled: true)
        network.vpn = true
        #expect(gate.isOpen)
        #expect(gate.isVPNConnected)
        try gate.check("test")
    }

    /// The answer is the probe's at the moment of the check, not a remembered one.
    @Test func everyCheckAsksAgain() throws {
        let (gate, network, _) = try gate(enabled: true)
        network.vpn = true
        try gate.check("test")
        network.vpn = false
        #expect(throws: ProviderGateError.self) { try gate.check("test") }
        #expect(network.asked == 2)
    }

    @Test func theSettingIsStored() throws {
        let (gate, _, defaults) = try gate(enabled: false)
        gate.isEnabled = true
        #expect(defaults.bool(forKey: ProviderGate.enabledKey))
        #expect(!gate.isOpen)
        gate.isEnabled = false
        #expect(gate.isOpen)
    }

    /// IPTV_TESTVPNGUARD=1: on for the run, nothing stored.
    @Test func forcedOnDoesNotStore() throws {
        let (gate, _, defaults) = try gate(enabled: false, forced: true)
        #expect(gate.isEnabled)
        #expect(!gate.isOpen)
        #expect(defaults.object(forKey: ProviderGate.enabledKey) == nil)
    }

    /// Announced once per change, on the main queue and after the check returned (a stream asks
    /// while it holds its lock).
    @MainActor @Test func changesAreAnnouncedOnceOnTheMainQueue() async throws {
        let (gate, network, _) = try gate(enabled: true)
        nonisolated(unsafe) var changes = 0
        nonisolated(unsafe) var offMain = 0
        let token = NotificationCenter.default.addObserver(forName: ProviderGate.didChange, object: gate, queue: nil) { _ in
            changes += 1
            if !Thread.isMainThread { offMain += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        func settled() async { await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } } }
        gate.refresh()
        gate.refresh()
        await settled()
        #expect(changes == 0)
        network.vpn = true
        gate.refresh()
        #expect(changes == 0, "announced inside the check")
        await settled()
        #expect(changes == 1)
        network.vpn = false
        // From another thread, as a stream's watchdog does.
        await Task.detached { _ = gate.isOpen }.value
        await settled()
        #expect(changes == 2)
        gate.isEnabled = false
        await settled()
        #expect(changes == 3)
        #expect(offMain == 0)
    }

    #else
    /// The Fernsy Server on Linux talks to the provider for its recordings: the gate stays open.
    @Test func alwaysOpenOnLinux() throws {
        let (gate, _, _) = try gate(enabled: true, forced: true)
        #expect(!gate.isEnabled)
        #expect(gate.isOpen)
        try gate.check("test")
    }
    #endif

    @Test func theErrorNamesTheVPN() {
        #expect(ProviderGateError.vpnRequired.localizedDescription.contains("VPN"))
    }
}
