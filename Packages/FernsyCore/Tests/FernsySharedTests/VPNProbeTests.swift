import Foundation
import Testing
@testable import FernsyShared

/// What counts as a VPN (vpn-guard 1.1, 1.3): the rule over the interfaces that carry internet
/// traffic per address family, and the faked answer of `IPTV_TESTVPN`.
struct VPNProbeTests {
    private func routes(_ ipv4: String?, _ ipv6: String?) -> VPNProbe.Routes {
        VPNProbe.Routes(ipv4: ipv4, ipv6: ipv6)
    }

    @Test func aFullTunnelOnBothFamiliesCounts() {
        #expect(routes("utun5", "utun5").usesTunnel)
        #expect(routes("ipsec0", "utun2").usesTunnel)
    }

    @Test func aTunnelForIPv4WithoutAnIPv6RouteCounts() {
        #expect(routes("utun5", nil).usesTunnel)
        #expect(routes(nil, "utun5").usesTunnel)
    }

    @Test func iPv6BesideTheTunnelDoesNotCount() {
        #expect(!routes("utun5", "en0").usesTunnel)
        #expect(!routes("en0", "utun5").usesTunnel)
    }

    /// A split tunnel (Tailscale without an exit node): the tunnel exists, the internet does not
    /// go through it.
    @Test func aTunnelThatIsNotUsedDoesNotCount() {
        #expect(!routes("en0", "en0").usesTunnel)
        #expect(!routes("en1", nil).usesTunnel)
        #expect(!routes("pdp_ip0", "pdp_ip0").usesTunnel)
    }

    @Test func noRouteAtAllDoesNotCount() {
        #expect(!routes(nil, nil).usesTunnel)
    }

    @Test(arguments: ["utun0", "utun18", "ipsec0", "ppp0", "tun0", "tap1"])
    func tunnelNames(_ name: String) {
        #expect(VPNProbe.isTunnel(name))
    }

    @Test(arguments: ["en0", "en12", "pdp_ip0", "bridge100", "lo0", "awdl0", "llw0", "anpi0"])
    func otherNames(_ name: String) {
        #expect(!VPNProbe.isTunnel(name))
    }

    @Test func theFakedAnswerWinsOverTheLookup() {
        var asked = 0
        let direct = { () -> VPNProbe.Routes in asked += 1; return VPNProbe.Routes(ipv4: "en0", ipv6: "en0") }
        let tunnel = { () -> VPNProbe.Routes in asked += 1; return VPNProbe.Routes(ipv4: "utun5") }
        #expect(VPNProbe.current(faked: true, lookup: direct).usesTunnel)
        #expect(!VPNProbe.current(faked: false, lookup: tunnel).usesTunnel)
        #expect(asked == 0)
        #expect(VPNProbe.current(faked: nil, lookup: tunnel).usesTunnel)
        #expect(!VPNProbe.current(faked: nil, lookup: direct).usesTunnel)
        #expect(asked == 2)
    }

    @Test func theLogTextNamesBothFamilies() {
        #expect(routes("utun5", nil).description == "IPv4 utun5, IPv6 no route")
    }

    #if canImport(Darwin)
    /// The real lookup answers with interface names (or no route), whatever this machine's network is.
    @Test func theLookupNamesInterfaces() {
        let found = VPNProbe.lookup()
        for name in [found.ipv4, found.ipv6].compactMap({ $0 }) {
            #expect(!name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" })
        }
    }
    #endif
}
