import Foundation
import Testing
@testable import FernsyPlayer

/// A film's download held far enough ahead, against a server that keeps sending while the task
/// is suspended (a Jellyfin film once ended up in memory as a whole, 3.7 GB, and Foundation
/// trapped when the buffer shrank below 2 GB): the source closes the connection, stays bounded,
/// and continues with a range request where it stopped.
@Suite(.serialized)
struct HeldDownloadTests {
    /// Serves a film fast and ignores the task being suspended.
    final class Server: URLProtocol, @unchecked Sendable {
        static let lock = NSLock()
        nonisolated(unsafe) static var ranges: [String?] = []
        nonisolated(unsafe) static var film = Data()
        static let queue = DispatchQueue(label: "test.held-server")

        static func requests() -> [String?] { lock.lock(); defer { lock.unlock() }; return ranges }

        private var timer: DispatchSourceTimer?

        override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "held.test" }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let url = request.url!
            let range = request.value(forHTTPHeaderField: "Range")
            Self.lock.lock(); Self.ranges.append(range); Self.lock.unlock()
            let film = Self.film
            var offset = range.flatMap { Int($0.dropFirst("bytes=".count).dropLast()) } ?? 0
            let headers = range == nil
                ? ["Accept-Ranges": "bytes", "Content-Length": "\(film.count)"]
                : ["Content-Range": "bytes \(offset)-\(film.count - 1)/\(film.count)", "Content-Length": "\(film.count - offset)"]
            let response = HTTPURLResponse(url: url, statusCode: range == nil ? 200 : 206, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let timer = DispatchSource.makeTimerSource(queue: Self.queue)
            self.timer = timer
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let end = min(film.count, offset + 64 << 10)
                if end > offset { self.client?.urlProtocol(self, didLoad: film.subdata(in: offset..<end)) }
                offset = end
                if offset >= film.count {
                    self.timer?.cancel()
                    self.client?.urlProtocolDidFinishLoading(self)
                }
            }
            timer.schedule(deadline: .now(), repeating: 0.005)
            timer.resume()
        }

        override func stopLoading() { timer?.cancel() }
    }

    init() {
        Server.lock.lock(); Server.ranges = []; Server.lock.unlock()
        var bytes = [UInt8](repeating: 0, count: 8 << 20)
        for i in bytes.indices { bytes[i] = UInt8(truncatingIfNeeded: i &* 31 &+ i >> 9) }
        Server.film = Data(bytes)
    }

    private func read(_ source: HTTPByteSource, _ count: Int) -> Data {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 32 << 10)
        while data.count < count {
            let n = chunk.withUnsafeMutableBufferPointer { source.read(into: $0.baseAddress!, size: min($0.count, count - data.count)) }
            guard n > 0 else { break }
            data.append(contentsOf: chunk[0..<Int(n)])
        }
        return data
    }

    private func ahead(_ source: HTTPByteSource) -> Int {
        source.cond.lock(); defer { source.cond.unlock() }
        return source.buffer.count
    }

    @Test func aHeldFilmStaysBoundedAndContinuesWhereItStopped() throws {
        let film = HTTPByteSource(url: URL(string: "https://held.test/Videos/1/stream")!, isLive: false,
                                  testWater: (high: 256 << 10, low: 64 << 10), testProtocols: [Server.self])
        try film.open()
        var received = read(film, 16 << 10)

        // Nobody reads: the server would deliver the whole film within a second.
        Thread.sleep(forTimeInterval: 1.5)
        let buffered = ahead(film)
        #expect(buffered < 1 << 20, "\(buffered >> 10) KB buffered while held")
        #expect(Server.requests().count == 1)

        received.append(read(film, Server.film.count))
        #expect(received.count == Server.film.count)
        #expect(received == Server.film)
        let continued = Server.requests().dropFirst()
        #expect(!continued.isEmpty && continued.allSatisfy { $0?.hasPrefix("bytes=") == true }, "\(Server.requests())")
        film.cancel()
    }
}
