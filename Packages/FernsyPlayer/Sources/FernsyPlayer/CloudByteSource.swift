import CFFShim
import CryptoKit
import FernsyCore
import Foundation

/// Plays a Fernsy Cloud recording (add-recording-cloud design C): FFmpeg reads plaintext
/// offsets, this source fetches the matching encrypted 1 MiB chunks with HTTP range requests on
/// the signed URL, decrypts them and keeps a bounded read-ahead and cache, sized for the Apple
/// TV. An expired URL (403) is replaced through `refreshURL`; a chunk that fails authentication
/// ends playback as a damaged recording instead of feeding altered data to the demuxer.
public final class CloudByteSource: ByteSource {
    public static let readAhead = 8
    public static let cacheLimit = 32
    static let parallelFetches = 4
    static let attempts = 4

    public let recordingId: String
    public let layout: CloudFileLayout
    private let key: SymmetricKey
    private let refreshURL: @Sendable () async throws -> URL
    private let urlSession: URLSession

    private let condition = NSCondition()
    private var dataURL: URL
    private var offset: Int64 = 0
    private var cancelled = false
    private var chunks: [Int: Data] = [:]
    private var lastUse: [Int: UInt64] = [:]
    private var useCounter: UInt64 = 0
    private var inflight: Set<Int> = []
    private var failure: String?
    private var received: Int64 = 0
    private var stats = HTTPByteSource.NetStats()

    public var tap: ((UnsafeBufferPointer<UInt8>) -> Void)?
    public var onRejoin: ((Int64) -> Void)?

    public init(recordingId: String, plaintextSize: Int64, fileKey: SymmetricKey, dataURL: URL,
                urlSession: URLSession = .shared, refreshURL: @escaping @Sendable () async throws -> URL) {
        self.recordingId = recordingId
        self.layout = CloudFileLayout(plaintextSize: plaintextSize)
        self.key = fileKey
        self.dataURL = dataURL
        self.urlSession = urlSession
        self.refreshURL = refreshURL
    }

    /// The URL the player keys this item by (resume positions, logs); never fetched.
    public static func itemURL(_ recordingId: String) -> URL { URL(string: "fernsy-cloud://recording/\(recordingId)")! }

    public var isCancelled: Bool { condition.withLock { cancelled } }
    public var supportsRanges: Bool { true }
    public var finalURL: URL? { Self.itemURL(recordingId) }
    public var mimeType: String? { "video/mp2t" }
    public var netStats: HTTPByteSource.NetStats { condition.withLock { stats } }
    public var totalBytesReceived: Int64 { condition.withLock { received } }
    public var failureMessage: String? { condition.withLock { failure } }

    public func open() throws {
        // The header tells a wrong or foreign object apart before FFmpeg probes it.
        let header = try blockingFetch(0..<Int64(CloudCrypto.headerSize))
        try CloudCrypto.checkHeader(header)
        schedule(from: 0)
    }

    public func cancel() {
        condition.withLock {
            cancelled = true
            condition.broadcast()
        }
    }

    public func read(into ptr: UnsafeMutablePointer<UInt8>, size: Int) -> Int32 {
        condition.lock()
        defer { condition.unlock() }
        let position = offset
        guard position < layout.plaintextSize else { return Int32(ffs_error_eof()) }
        let index = layout.chunk(containing: position)
        startFetches(around: index)
        while chunks[index] == nil {
            if cancelled { return Int32(ffs_error_exit()) }
            if failure != nil { return Int32(ffs_error_eio()) }
            if !inflight.contains(index) { startFetches(around: index) }
            condition.wait()
        }
        let chunk = chunks[index]!
        useCounter += 1
        lastUse[index] = useCounter
        let start = Int(position - layout.plaintextRange(ofChunk: index).lowerBound)
        let count = min(size, chunk.count - start)
        chunk.withUnsafeBytes { raw in
            ptr.update(from: raw.bindMemory(to: UInt8.self).baseAddress! + start, count: count)
        }
        offset = position + Int64(count)
        tap?(UnsafeBufferPointer(start: ptr, count: count))
        return Int32(count)
    }

    public func seek(offset target: Int64, whence: Int32) -> Int64 {
        if whence & Int32(ffs_avseek_size()) != 0 { return layout.plaintextSize }
        let mode = whence & ~Int32(ffs_avseek_force())
        condition.lock()
        defer { condition.unlock() }
        let position: Int64
        switch mode {
        case SEEK_SET: position = target
        case SEEK_CUR: position = offset + target
        case SEEK_END: position = layout.plaintextSize + target
        default: return -1
        }
        guard position >= 0 else { return -1 }
        offset = position
        if position < layout.plaintextSize { startFetches(around: layout.chunk(containing: position)) }
        return position
    }

    public func reportPlaybackAhead(_ seconds: Double) {}

    // MARK: Fetching

    private func schedule(from index: Int) {
        condition.withLock { startFetches(around: index) }
    }

    /// Lock held. Fetches the chunk at `index` and the read-ahead behind it, a few at a time.
    private func startFetches(around index: Int) {
        guard failure == nil, !cancelled else { return }
        let last = min(layout.chunkCount - 1, index + Self.readAhead)
        guard index <= last else { return }
        for i in index...last where chunks[i] == nil && !inflight.contains(i) {
            if inflight.count >= Self.parallelFetches && i != index { break }
            inflight.insert(i)
            Task.detached(priority: .userInitiated) { [weak self] in await self?.fetch(i) }
        }
    }

    private func fetch(_ index: Int) async {
        let range = layout.ciphertextRange(ofChunk: index)
        var lastError = ""
        for attempt in 0..<Self.attempts {
            if isCancelled { break }
            do {
                let sealed = try await fetchRange(range)
                let plain = try CloudCrypto.openChunk(sealed, index: index, isLast: layout.isLast(index), key: key, recordingId: recordingId)
                store(plain, at: index, bytes: Int64(sealed.count))
                return
            } catch CloudCrypto.Failure.damaged {
                AppLog.warning(.player, "Fernsy Cloud: chunk \(index) of \(recordingId.prefix(8)) failed authentication")
                fail(String(localized: "This recording is damaged and cannot be played.", bundle: .module))
                return
            } catch {
                lastError = error.localizedDescription
                try? await Task.sleep(for: .milliseconds(300 * (attempt + 1)))
            }
        }
        if !isCancelled {
            AppLog.warning(.player, "Fernsy Cloud: chunk \(index) not loaded: \(lastError)")
            fail(String(localized: "Connection lost", bundle: .module))
        }
    }

    struct Expired: Error {}
    struct BadStatus: Error, LocalizedError {
        let status: Int
        var errorDescription: String? { "HTTP \(status)" }
    }

    /// One range request; on 403 the URL is renewed once and the request repeated.
    private func fetchRange(_ range: Range<Int64>) async throws -> Data {
        for renewed in [false, true] {
            var request = URLRequest(url: condition.withLock { dataURL })
            request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
            request.timeoutInterval = 20
            let started = Date()
            let (data, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            condition.withLock { stats.connectTime = Date().timeIntervalSince(started) }
            if status == 206 || (status == 200 && range.lowerBound == 0 && Int64(data.count) == range.count) {
                guard Int64(data.count) == range.count else { throw BadStatus(status: status) }
                return data
            }
            if (status == 403 || status == 401) && !renewed {
                let fresh = try await refreshURL()
                AppLog.info(.player, "Fernsy Cloud: streaming URL renewed for \(recordingId.prefix(8))")
                condition.withLock { dataURL = fresh }
                continue
            }
            throw BadStatus(status: status)
        }
        throw Expired()
    }

    private func blockingFetch(_ range: Range<Int64>) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<Data, Error> = .failure(Expired())
        Task.detached { [self] in
            do { result = .success(try await fetchRange(range)) } catch { result = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return try result.get()
    }

    private func store(_ plain: Data, at index: Int, bytes: Int64) {
        condition.withLock {
            inflight.remove(index)
            received += bytes
            chunks[index] = plain
            useCounter += 1
            lastUse[index] = useCounter
            evict(keeping: index)
            condition.broadcast()
            startFetches(around: layout.chunk(containing: min(offset, max(0, layout.plaintextSize - 1))))
        }
    }

    /// Lock held. Drops least recently used chunks outside the window at the read position.
    private func evict(keeping index: Int) {
        guard chunks.count > Self.cacheLimit else { return }
        let current = offset < layout.plaintextSize ? layout.chunk(containing: offset) : layout.chunkCount
        let window = current...(current + Self.readAhead)
        let candidates = chunks.keys.filter { !window.contains($0) && $0 != index }.sorted { (lastUse[$0] ?? 0) < (lastUse[$1] ?? 0) }
        for victim in candidates.prefix(chunks.count - Self.cacheLimit) {
            chunks[victim] = nil
            lastUse[victim] = nil
        }
    }

    private func fail(_ message: String) {
        condition.withLock {
            if failure == nil { failure = message }
            inflight.removeAll()
            condition.broadcast()
        }
    }

    /// Tests: how many decrypted chunks are held.
    var cachedChunkCount: Int { condition.withLock { chunks.count } }
}
