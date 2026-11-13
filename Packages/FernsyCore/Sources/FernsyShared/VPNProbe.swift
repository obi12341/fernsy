import Foundation

/// Whether the device's internet traffic leaves through a VPN tunnel (vpn-guard design 2). The
/// kernel is asked which interface would carry a packet to a public address, per address
/// family; nothing is sent for that.
public enum VPNProbe {
    /// The interface that carries internet traffic per address family; nil = no route.
    public struct Routes: Equatable, Sendable, CustomStringConvertible {
        public var ipv4: String?
        public var ipv6: String?

        public init(ipv4: String? = nil, ipv6: String? = nil) {
            self.ipv4 = ipv4
            self.ipv6 = ipv6
        }

        /// Every family that has a route leaves through a tunnel, and at least one has a route.
        /// A tunnel beside a direct route of the other family does not count: that family leaks.
        public var usesTunnel: Bool {
            let used = [ipv4, ipv6].compactMap { $0 }
            return !used.isEmpty && used.allSatisfy(VPNProbe.isTunnel)
        }

        public var description: String {
            "IPv4 \(ipv4 ?? "no route"), IPv6 \(ipv6 ?? "no route")"
        }
    }

    /// Interface names of VPN tunnels (`utun3`, `ipsec0`, `ppp0`, `tun0`, `tap0`).
    public static func isTunnel(_ interface: String) -> Bool {
        ["utun", "ipsec", "ppp", "tun", "tap"].contains { interface.hasPrefix($0) }
    }

    /// `IPTV_TESTVPN=on|off[,<s>:on|off…]` (debug builds): the answer instead of the lookup, so
    /// the guard can be tested without a VPN; later steps change it that many seconds after the
    /// first look (`on,20:off,50:on`). The debug MCP tool `set_vpn` switches it during a run.
    #if DEBUG
    nonisolated(unsafe) public static var testAnswer: Bool? = {
        let steps = (ProcessInfo.processInfo.environment["IPTV_TESTVPN"] ?? "").split(separator: ",")
        guard let first = steps.first, let start = answer(first) else { return nil }
        for step in steps.dropFirst() {
            let parts = step.split(separator: ":")
            guard parts.count == 2, let delay = Double(parts[0]), let value = answer(parts[1]) else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                testAnswer = value
                ProviderGate.shared.refresh()
            }
        }
        return start
    }()

    private static func answer(_ text: Substring) -> Bool? {
        text == "on" ? true : text == "off" ? false : nil
    }
    #else
    public static let testAnswer: Bool? = nil
    #endif

    /// The routes now: the faked answer if there is one, else the lookup.
    public static func current(faked: Bool? = testAnswer, lookup: () -> Routes = lookup) -> Routes {
        switch faked {
        case true?: Routes(ipv4: "utun-test")
        case false?: Routes(ipv4: "en-test")
        case nil: lookup()
        }
    }

    /// Asks the kernel. Public addresses that stand for "the internet": the provider's own would
    /// need a DNS query first, and streams are redirected to hosts not known in advance.
    public static func lookup() -> Routes {
        #if canImport(Darwin)
        Routes(ipv4: interface(to: "1.1.1.1", family: AF_INET), ipv6: interface(to: "2606:4700:4700::1111", family: AF_INET6))
        #else
        Routes()
        #endif
    }

    #if canImport(Darwin)
    /// The interface a packet to `address` would leave through. Connecting a UDP socket sends
    /// nothing: it only makes the kernel choose the route and with it the local address.
    private static func interface(to address: String, family: Int32) -> String? {
        let fd = socket(family, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let connected: Int32
        if family == AF_INET {
            var to = sockaddr_in()
            to.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            to.sin_family = sa_family_t(AF_INET)
            to.sin_port = UInt16(443).bigEndian
            guard inet_pton(AF_INET, address, &to.sin_addr) == 1 else { return nil }
            connected = withUnsafePointer(to: &to) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        } else {
            var to = sockaddr_in6()
            to.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            to.sin6_family = sa_family_t(AF_INET6)
            to.sin6_port = UInt16(443).bigEndian
            guard inet_pton(AF_INET6, address, &to.sin6_addr) == 1 else { return nil }
            connected = withUnsafePointer(to: &to) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
            }
        }
        guard connected == 0 else { return nil }
        var local = sockaddr_storage()
        var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let named = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { return nil }
        return owner(of: local, family: family)
    }

    /// The interface that has `local` as one of its addresses.
    private static func owner(of local: sockaddr_storage, family: Int32) -> String? {
        var local = local
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var entry = list
        while let current = entry {
            entry = current.pointee.ifa_next
            guard let address = current.pointee.ifa_addr, Int32(address.pointee.sa_family) == family else { continue }
            let same: Bool
            if family == AF_INET {
                let mine = withUnsafePointer(to: &local) {
                    $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
                }
                same = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr } == mine
            } else {
                var mine = withUnsafePointer(to: &local) {
                    $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                }
                var theirs = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                same = memcmp(&mine, &theirs, MemoryLayout<in6_addr>.size) == 0
            }
            if same { return String(cString: current.pointee.ifa_name) }
        }
        return nil
    }
    #endif
}
