import CFFShim
import CryptoKit
import FernsyCore
import Foundation
import Testing
@testable import FernsyPlayer

/// Streaming a Fernsy Cloud recording (add-recording-cloud 4.1) from a stubbed storage that
/// answers range requests: reading through, seeking to the middle, an expired URL mid-play, and a
/// corrupted chunk that ends playback as damaged.
@Suite(.serialized)
struct CloudByteSourceTests {
    final class Storage: URLProtocol {
        nonisolated(unsafe) static var object = Data()
        /// URLs that answer 403 (expired).
        nonisolated(unsafe) static var expired: Set<String> = []
        nonisolated(unsafe) static var requests = 0
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.requests += 1
            let url = request.url!
            if Self.expired.contains(url.absoluteString) {
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let header = request.value(forHTTPHeaderField: "Range")!.dropFirst("bytes=".count).split(separator: "-").map { Int($0)! }
            let body = Self.object[header[0]...min(header[1], Self.object.count - 1)]
            let response = HTTPURLResponse(url: url, statusCode: 206, httpVersion: nil, headerFields: ["Content-Length": "\(body.count)"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Storage.self]
        return URLSession(configuration: config)
    }

    /// TS-like plaintext and its encrypted object.
    static func prepare(bytes: Int, id: String) throws -> (plain: Data, key: SymmetricKey) {
        let plain = Data((0..<bytes).map { $0 % 188 == 0 ? 0x47 : UInt8(truncatingIfNeeded: $0 &* 7) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cbs-\(UUID()).ts")
        try plain.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let key = CloudCrypto.newFileKey()
        let encryptor = try CloudFileEncryptor(url: url, plaintextSize: Int64(bytes), key: key, recordingId: id)
        Storage.object = try encryptor.bytes(in: 0..<encryptor.layout.ciphertextSize)
        Storage.expired = []
        Storage.requests = 0
        return (plain, key)
    }

    static func readAll(_ source: CloudByteSource, from start: Int64 = 0) -> (Data, Int32) {
        _ = source.seek(offset: start, whence: SEEK_SET)
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = buffer.withUnsafeMutableBufferPointer { source.read(into: $0.baseAddress!, size: $0.count) }
            if n <= 0 { return (out, n) }
            out.append(buffer, count: Int(n))
        }
    }

    @Test func readsThroughAndSeeks() throws {
        let size = 12 * CloudCrypto.chunkSize + 4321
        let (plain, key) = try Self.prepare(bytes: size, id: "r1")
        let source = CloudByteSource(recordingId: "r1", plaintextSize: Int64(size), fileKey: key, dataURL: URL(string: "https://r2.test/a")!,
                                     urlSession: Self.session) { URL(string: "https://r2.test/a")! }
        try source.open()
        #expect(source.seek(offset: 0, whence: Int32(ffs_avseek_size())) == Int64(size))
        let (all, end) = Self.readAll(source)
        #expect(end == Int32(ffs_error_eof()))
        #expect(all == plain)
        #expect(source.cachedChunkCount <= CloudByteSource.cacheLimit)
        let middle = Int64(size / 2 + 77)
        let (tail, _) = Self.readAll(source, from: middle)
        #expect(tail == plain[Int(middle)...])
    }

    @Test func expiredURLIsRenewed() throws {
        let size = 4 * CloudCrypto.chunkSize
        let (plain, key) = try Self.prepare(bytes: size, id: "r2")
        let renewals = Counter()
        let source = CloudByteSource(recordingId: "r2", plaintextSize: Int64(size), fileKey: key, dataURL: URL(string: "https://r2.test/old")!,
                                     urlSession: Self.session) {
            renewals.increment()
            return URL(string: "https://r2.test/new")!
        }
        try source.open()
        Storage.expired = ["https://r2.test/old"]
        let (all, _) = Self.readAll(source, from: Int64(2 * CloudCrypto.chunkSize))
        #expect(all == plain[(2 * CloudCrypto.chunkSize)...])
        #expect(renewals.value >= 1)
    }

    @Test func damagedChunkEndsPlayback() throws {
        let size = 6 * CloudCrypto.chunkSize
        let (_, key) = try Self.prepare(bytes: size, id: "r3")
        let layout = CloudFileLayout(plaintextSize: Int64(size))
        Storage.object[Int(layout.ciphertextRange(ofChunk: 2).lowerBound) + 10] ^= 0xFF
        let source = CloudByteSource(recordingId: "r3", plaintextSize: Int64(size), fileKey: key, dataURL: URL(string: "https://r2.test/a")!,
                                     urlSession: Self.session) { URL(string: "https://r2.test/a")! }
        try source.open()
        let (read, end) = Self.readAll(source)
        #expect(end == Int32(ffs_error_eio()))
        #expect(read.count <= 2 * CloudCrypto.chunkSize)
        #expect(source.failureMessage != nil)
    }

    @Test func foreignObjectIsRefused() throws {
        _ = try Self.prepare(bytes: CloudCrypto.chunkSize, id: "r4")
        Storage.object.replaceSubrange(0..<4, with: Data("XXXX".utf8))
        let source = CloudByteSource(recordingId: "r4", plaintextSize: Int64(CloudCrypto.chunkSize), fileKey: CloudCrypto.newFileKey(),
                                     dataURL: URL(string: "https://r2.test/a")!, urlSession: Self.session) { URL(string: "https://r2.test/a")! }
        #expect(throws: CloudCrypto.Failure.badHeader) { try source.open() }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    // MARK: Downloads (offline-recording-downloads 2.1)

    /// The encrypted object written to a file, as a download stores it.
    static func downloaded() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cbs-\(UUID()).data")
        try Storage.object.write(to: url)
        return url
    }

    @Test func playsADownloadWithoutNetwork() throws {
        let size = 12 * CloudCrypto.chunkSize + 4321
        let (plain, key) = try Self.prepare(bytes: size, id: "d1")
        let file = try Self.downloaded()
        defer { try? FileManager.default.removeItem(at: file) }
        let source = try CloudByteSource(recordingId: "d1", plaintextSize: Int64(size), fileKey: key, file: file)
        try source.open()
        let (all, end) = Self.readAll(source)
        #expect(end == Int32(ffs_error_eof()))
        #expect(all == plain)
        // Seeking across a chunk boundary.
        let middle = Int64(5 * CloudCrypto.chunkSize - 9)
        let (tail, _) = Self.readAll(source, from: middle)
        #expect(tail == plain[Int(middle)...])
        #expect(Storage.requests == 0, "a download never touches the network")
    }

    @Test func damagedDownloadEndsPlayback() throws {
        let size = 6 * CloudCrypto.chunkSize
        let (_, key) = try Self.prepare(bytes: size, id: "d2")
        let layout = CloudFileLayout(plaintextSize: Int64(size))
        Storage.object[Int(layout.ciphertextRange(ofChunk: 3).lowerBound) + 99] ^= 0x01
        let file = try Self.downloaded()
        defer { try? FileManager.default.removeItem(at: file) }
        let source = try CloudByteSource(recordingId: "d2", plaintextSize: Int64(size), fileKey: key, file: file)
        try source.open()
        let (read, end) = Self.readAll(source)
        #expect(end == Int32(ffs_error_eio()))
        #expect(read.count <= 3 * CloudCrypto.chunkSize)
        #expect(source.failureMessage != nil)
    }
}

