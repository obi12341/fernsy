import Combine
import Foundation
import Testing
@testable import FernsyCore

/// What the views and models see of "IPTV only with VPN" (vpn-guard design 8).
@MainActor
struct VPNGuardStateTests {
    final class Network: @unchecked Sendable {
        var vpn = false
    }

    private func make(enabled: Bool) throws -> (VPNGuardState, ProviderGate, Network) {
        let defaults = try #require(UserDefaults(suiteName: "guard-state-\(UUID().uuidString)"))
        if enabled { defaults.set(true, forKey: ProviderGate.enabledKey) }
        let network = Network()
        let gate = ProviderGate(defaults: defaults) { VPNProbe.current(faked: network.vpn) }
        return (VPNGuardState(gate: gate, interval: 3600), gate, network)
    }

    @Test func blocksWhileOnWithoutAVPN() throws {
        let (state, _, network) = try make(enabled: true)
        #expect(state.isEnabled && state.isBlocking)
        network.vpn = true
        state.update()
        #expect(state.isVPNConnected && !state.isBlocking)
    }

    @Test func tellsWhenTheProviderCanBeReachedAgain() throws {
        let (state, _, network) = try make(enabled: true)
        var reopened = 0
        let token = state.reopened.sink { reopened += 1 }
        defer { token.cancel() }
        state.update()
        #expect(reopened == 0)
        network.vpn = true
        state.update()
        #expect(reopened == 1)
        state.update()
        #expect(reopened == 1)
        network.vpn = false
        state.update()
        state.setEnabled(false)
        #expect(reopened == 2, "switching the setting off opens the provider too")
    }

    @Test func offNeverBlocksButShowsTheVPNWhileWatched() throws {
        let (state, _, network) = try make(enabled: false)
        #expect(!state.isBlocking)
        network.vpn = true
        state.update()
        #expect(!state.isVPNConnected, "not looked at while nobody shows it")
        state.watch(true)
        #expect(state.isVPNConnected)
        network.vpn = false
        state.update()
        #expect(!state.isVPNConnected && !state.isBlocking)
        state.watch(false)
    }

    /// A check elsewhere (a stream noticing the missing VPN) reaches the views without the timer.
    @Test func followsTheGatesAnnouncements() async throws {
        let (state, gate, network) = try make(enabled: true)
        network.vpn = true
        state.update()
        network.vpn = false
        #expect(!gate.isOpen)
        for _ in 0..<50 where !state.isBlocking { try await Task.sleep(for: .milliseconds(20)) }
        #expect(state.isBlocking)
    }
}
