import CFFShim
import FernsyCore
import Foundation
import Testing
@testable import FernsyPlayer

/// "IPTV only with VPN" in the stream source (vpn-guard 3.3), against a stubbed provider: a first
/// connection without a VPN is refused, a stream that runs waits for the VPN without spending
/// reconnect attempts and goes on when it is back, and a waiting source can be cancelled.
@Suite(.serialized)
struct VPNGuardSourceTests {
    /// A provider that streams a live channel without end and serves a film with ranges, slowly
    /// enough for a test to interrupt it.
    final class Provider: URLProtocol, @unchecked Sendable {
        static let lock = NSLock()
        /// Host and Range header of every request, in order. The recorder's tests use another
        /// host: the suites may run side by side.
        nonisolated(unsafe) static var seen: [(host: String, range: String?)] = []
        nonisolated(unsafe) static var open: [Provider] = []
        nonisolated(unsafe) static var film = Data()
        static let queue = DispatchQueue(label: "test.provider")

        static func ranges(to host: String = "provider.test") -> [String?] {
            lock.lock(); defer { lock.unlock() }
            return seen.filter { $0.host == host }.map(\.range)
        }
        static func requests(to host: String = "provider.test") -> Int { ranges(to: host).count }
        static func reset(_ host: String = "provider.test") { lock.lock(); seen.removeAll { $0.host == host }; lock.unlock() }
        /// Every open connection fails, as when its interface goes away.
        static func dropAll() {
            lock.lock(); let all = open.filter { $0.request.url?.host == "provider.test" }; open.removeAll { all.contains($0) }; lock.unlock()
            for connection in all {
                connection.timer?.cancel()
                connection.client?.urlProtocol(connection, didFailWithError: URLError(.networkConnectionLost))
            }
        }

        private var timer: DispatchSourceTimer?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let url = request.url!
            let range = request.value(forHTTPHeaderField: "Range")
            Self.lock.lock(); Self.seen.append((url.host ?? "", range)); Self.open.append(self); Self.lock.unlock()
            let timer = DispatchSource.makeTimerSource(queue: Self.queue)
            self.timer = timer
            if url.path.hasPrefix("/live/") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "video/mp2t"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                timer.setEventHandler { [weak self] in
                    guard let self else { return }
                    self.client?.urlProtocol(self, didLoad: Data(repeating: 0x47, count: 188 * 40))
                }
            } else {
                let film = Self.film
                var offset = range.flatMap { Int($0.dropFirst("bytes=".count).dropLast()) } ?? 0
                let headers = range == nil
                    ? ["Accept-Ranges": "bytes", "Content-Length": "\(film.count)"]
                    : ["Content-Range": "bytes \(offset)-\(film.count - 1)/\(film.count)", "Content-Length": "\(film.count - offset)"]
                let response = HTTPURLResponse(url: url, statusCode: range == nil ? 200 : 206, httpVersion: "HTTP/1.1", headerFields: headers)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                timer.setEventHandler { [weak self] in
                    guard let self else { return }
                    let end = min(film.count, offset + 16 << 10)
                    if end > offset { self.client?.urlProtocol(self, didLoad: film.subdata(in: offset..<end)) }
                    offset = end
                    if offset >= film.count {
                        self.timer?.cancel()
                        self.client?.urlProtocolDidFinishLoading(self)
                    }
                }
            }
            timer.schedule(deadline: .now(), repeating: 0.02)
            timer.resume()
        }

        override func stopLoading() {
            timer?.cancel()
            Self.lock.lock(); Self.open.removeAll { $0 === self }; Self.lock.unlock()
        }
    }

    final class Network: @unchecked Sendable {
        var vpn = true
    }

    let network = Network()
    let gate: ProviderGate

    init() throws {
        HTTPByteSource.testProtocolClasses = [Provider.self]
        Provider.reset()
        let defaults = try #require(UserDefaults(suiteName: "source-gate-\(UUID().uuidString)"))
        defaults.set(true, forKey: ProviderGate.enabledKey)
        let network = network
        gate = ProviderGate(defaults: defaults) { VPNProbe.current(faked: network.vpn) }
    }

    private func source(_ path: String, live: Bool, guarded: Bool = true) -> HTTPByteSource {
        HTTPByteSource(url: URL(string: "https://provider.test\(path)")!, isLive: live, gate: guarded ? gate : nil)
    }

    private func read(_ source: HTTPByteSource, _ count: Int) -> Data {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 64 << 10)
        while data.count < count {
            let n = chunk.withUnsafeMutableBufferPointer { source.read(into: $0.baseAddress!, size: min($0.count, count - data.count)) }
            guard n > 0 else { break }
            data.append(contentsOf: chunk[0..<Int(n)])
        }
        return data
    }

    private func wait(_ seconds: Double, until done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if done() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return done()
    }

    private func held(_ source: HTTPByteSource) -> Bool {
        source.cond.lock(); defer { source.cond.unlock() }
        return source.heldForVPN
    }

    @Test func aFirstConnectionWithoutAVPNIsRefused() {
        network.vpn = false
        let live = source("/live/demo/demo/101.ts", live: true)
        #expect(throws: ProviderGateError.self) { try live.open() }
        let film = source("/movie/demo/demo/500.mp4", live: false)
        #expect(throws: ProviderGateError.self) { try film.open() }
        #expect(Provider.requests() == 0)
        live.cancel(); film.cancel()
    }

    @Test func aStreamThatIsNotTheProvidersIsNotAsked() throws {
        network.vpn = false
        let jellyfin = source("/live/jellyfin", live: true, guarded: false)
        try jellyfin.open()
        #expect(read(jellyfin, 188 * 10).count == 188 * 10)
        Thread.sleep(forTimeInterval: 1.6)
        #expect(Provider.requests() == 1)
        #expect(!held(jellyfin))
        jellyfin.cancel()
    }

    /// The VPN goes away under a connection that stays up (as with the debug switch): the source
    /// cuts it, asks nothing while it waits, and reconnects by itself.
    @Test func aRunningChannelWaitsForTheVPN() throws {
        let live = source("/live/demo/demo/101.ts", live: true)
        nonisolated(unsafe) var healths: [HTTPByteSource.Health] = []
        live.onHealth = { healths.append($0) }
        try live.open()
        #expect(read(live, 188 * 10).count == 188 * 10)

        network.vpn = false
        #expect(wait(3) { held(live) }, "the source did not notice the missing VPN")
        Thread.sleep(forTimeInterval: 2.5)
        #expect(Provider.requests() == 1)
        #expect(held(live))
        #expect(live.reconnectAttempts == 0)
        #expect(wait(1) { healths.last == .waitingForVPN }, "health: \(healths)")

        let before = live.totalBytesReceived
        network.vpn = true
        #expect(wait(3) { Provider.requests() == 2 }, "no reconnect after the VPN came back")
        #expect(wait(3) { live.totalBytesReceived > before })
        #expect(!held(live))
        #expect(wait(3) { healths.last != .waitingForVPN }, "health: \(healths)")
        live.cancel()
    }

    /// The connection breaks with the VPN: that drop is the one attempt; waiting adds none.
    @Test func waitingSpendsNoReconnectAttempts() throws {
        let live = source("/live/demo/demo/101.ts", live: true)
        try live.open()
        #expect(read(live, 188 * 10).count == 188 * 10)
        network.vpn = false
        Provider.dropAll()
        #expect(wait(3) { held(live) })
        Thread.sleep(forTimeInterval: 4)
        #expect(Provider.requests() == 1)
        #expect(live.reconnectAttempts <= 1)
        network.vpn = true
        #expect(wait(3) { Provider.requests() == 2 })
        live.cancel()
    }

    @Test func aFilmWaitsAndContinuesWhereItStopped() throws {
        var bytes = [UInt8](repeating: 0, count: 2 << 20)
        for i in bytes.indices { bytes[i] = UInt8(truncatingIfNeeded: i &* 31 &+ i >> 9) }
        Provider.film = Data(bytes)
        let film = source("/movie/demo/demo/500.mp4", live: false)
        try film.open()
        var received = read(film, 64 << 10)

        network.vpn = false
        #expect(wait(3) { held(film) }, "the download went on without a VPN")
        let stoppedAt = film.totalBytesReceived
        #expect(stoppedAt < Int64(Provider.film.count))
        Thread.sleep(forTimeInterval: 2)
        #expect(Provider.requests() == 1)
        #expect(film.totalBytesReceived == stoppedAt)

        network.vpn = true
        #expect(wait(3) { Provider.requests() == 2 }, "the download did not continue")
        #expect(Provider.ranges().last == "bytes=\(stoppedAt)-")
        received.append(read(film, Provider.film.count))
        #expect(received == Provider.film)
        film.cancel()
    }

    @Test func aWaitingSourceCanBeCancelled() throws {
        let live = source("/live/demo/demo/101.ts", live: true)
        try live.open()
        network.vpn = false
        #expect(wait(3) { held(live) })
        nonisolated(unsafe) var result: Int32 = 0
        let reader = Thread {
            var chunk = [UInt8](repeating: 0, count: 4096)
            // Drain what is buffered, then block.
            while true {
                result = chunk.withUnsafeMutableBufferPointer { live.read(into: $0.baseAddress!, size: $0.count) }
                if result <= 0 { break }
            }
        }
        reader.start()
        Thread.sleep(forTimeInterval: 0.5)
        live.cancel()
        #expect(wait(2) { reader.isFinished })
        #expect(result == Int32(ffs_error_exit()))
        network.vpn = true
        Thread.sleep(forTimeInterval: 1.5)
        #expect(Provider.requests() == 1)
    }
}
