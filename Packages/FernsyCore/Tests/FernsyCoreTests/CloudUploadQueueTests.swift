import Foundation
import Testing
@testable import FernsyCore

/// The Mac's upload queue (add-recording-cloud 5.4): a whole upload, continuing after a quit
/// with the parts already stored, cancelling, and refusing an upload over the quota.
@MainActor
@Suite(.serialized)
struct CloudUploadQueueTests {
    /// A server and storage in memory; `failPart` makes one part's PUT fail once (network loss).
    final class FakeAPI: CloudUploadAPI, @unchecked Sendable {
        let lock = NSLock()
        var stored: [String: Data] = [:]
        var parts: [String: [Int: Data]] = [:]
        var completed: [String: Data] = [:]
        var deleted: [String] = []
        var puts = 0
        var stopAfterPuts: Int?
        var quotaFree: Int64?
        /// How long a part's PUT takes, by part number (default `delay`), and parts that fail once.
        var delay: Duration?
        var partDelay: [Int: Duration] = [:]
        var failOnce: Set<Int> = []
        /// URLs handed out with the start (the rest come from `partURLs` batches).
        var initialURLs = 20
        var inFlight = 0
        var maxInFlight = 0
        var partPuts: [Int: Int] = [:]
        var partURLCalls = 0

        func startUpload(dataBytes: Int64, metaBytes: Int64, partSize: Int) async throws -> CloudClient.Upload {
            if let free = quotaFree, dataBytes + metaBytes > free { throw CloudClient.Failure.quota(needed: dataBytes + metaBytes, free: free) }
            let id = UUID().uuidString.lowercased()
            let count = Int((dataBytes + Int64(partSize) - 1) / Int64(partSize))
            return CloudClient.Upload(id: id, uploadId: "up-\(id)", partSize: partSize, partCount: count,
                                      partURLs: (1...min(count, initialURLs)).map { .init(number: $0, url: URL(string: "https://r2.test/\(id)/\($0)")!) },
                                      metaURL: URL(string: "https://r2.test/\(id)/meta")!)
        }
        func partURLs(id: String, numbers: [Int], meta: Bool) async throws -> (parts: [CloudClient.PartURL], metaURL: URL?) {
            lock.withLock { partURLCalls += 1 }
            return (numbers.map { .init(number: $0, url: URL(string: "https://r2.test/\(id)/\($0)")!) }, meta ? URL(string: "https://r2.test/\(id)/meta") : nil)
        }
        func complete(id: String, parts: [CloudClient.CompletedPart]) async throws {
            try lock.withLock {
                guard stored["\(id).meta"] != nil else { throw CloudClient.Failure.server(status: 400, code: "incomplete") }
                completed[id] = parts.reduce(into: Data()) { $0.append(self.parts[id]![$1.number]!) }
            }
        }
        func delete(id: String) async throws { lock.withLock { deleted.append(id) } }
        func put(_ data: Data, to url: URL) async throws -> String {
            let last = url.lastPathComponent
            let wait = lock.withLock { () -> Duration? in
                inFlight += 1
                maxInFlight = max(maxInFlight, inFlight)
                return Int(last).flatMap { partDelay[$0] } ?? delay
            }
            defer { lock.withLock { inFlight -= 1 } }
            if let wait { try await Task.sleep(for: wait) }
            return try lock.withLock {
                if let number = Int(last), failOnce.remove(number) != nil { throw CloudClient.Failure.network("offline") }
                if let stop = stopAfterPuts, puts >= stop { throw CloudClient.Failure.network("offline") }
                puts += 1
                let id = url.pathComponents[1]
                if last == "meta" { stored["\(id).meta"] = data } else {
                    parts[id, default: [:]][Int(last)!] = data
                    partPuts[Int(last)!, default: 0] += 1
                }
                return "etag-\(last)"
            }
        }
    }

    static func file(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("up-\(UUID()).ts")
        let block = Data((0..<CloudCrypto.chunkSize).map { UInt8(truncatingIfNeeded: $0 &* 13) })
        var data = Data(capacity: bytes)
        while data.count < bytes { data.append(block.prefix(bytes - data.count)) }
        try data.write(to: url)
        return url
    }

    static func meta(bytes: Int) -> CloudRecordingMeta {
        CloudRecordingMeta(title: "Tatort", channel: "Das Erste", showStart: nil, showEnd: nil, recordStart: .now, recordEnd: .now,
                           plaintextBytes: Int64(bytes), fileKey: CloudCrypto.newFileKey().withUnsafeBytes { Data($0) })
    }

    static func keys() -> CloudKeyStore {
        let key = CloudAccountKey()
        return CloudKeyStore(backing: nil, loadLocal: { key }, saveLocal: { _ in })
    }

    static func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func uploadsAndContinuesAfterQuit() async throws {
        let size = 33 * CloudCrypto.chunkSize + 5   // three parts
        let url = try Self.file(bytes: size)
        defer { try? FileManager.default.removeItem(at: url) }
        let state = FileManager.default.temporaryDirectory.appendingPathComponent("queue-\(UUID()).json")
        let api = FakeAPI()
        api.stopAfterPuts = 2   // meta and part 1 go through, then the network is gone
        let keys = Self.keys()
        let local = UUID()
        let meta = Self.meta(bytes: size)

        let first = CloudUploadQueue(api: api, keys: keys, stateURL: state)
        first.retryDelay = .seconds(60)
        first.enqueue(id: local, fileURL: url, meta: meta)
        await Self.waitUntil { first.job(for: local)?.state == .waiting }
        #expect(first.job(for: local)?.doneParts.count == 1)
        first.pause()

        // "Quit" and open again: the saved job continues with part 2.
        api.stopAfterPuts = nil
        let second = CloudUploadQueue(api: api, keys: keys, stateURL: state)
        #expect(second.job(for: local)?.doneParts.count == 1)
        second.resume()
        await Self.waitUntil { second.uploaded[local] != nil }
        let cloudId = try #require(second.uploaded[local])
        #expect(second.jobs.isEmpty)
        #expect(api.puts == 4)   // meta + three parts, part 1 only once
        let object = try #require(api.completed[cloudId])
        #expect(Int64(object.count) == CloudFileLayout(plaintextSize: Int64(size)).ciphertextSize)
        // Decrypts back to the file.
        let layout = CloudFileLayout(plaintextSize: Int64(size))
        let last = layout.chunkCount - 1
        let range = layout.ciphertextRange(ofChunk: last)
        let plain = try CloudCrypto.openChunk(object[Int(range.lowerBound)..<Int(range.upperBound)], index: last, isLast: true, key: meta.key, recordingId: cloudId)
        #expect(plain == (try Data(contentsOf: url)).suffix(5))
        // Queuing it again does nothing.
        second.enqueue(id: local, fileURL: url, meta: meta)
        #expect(second.jobs.isEmpty)
    }

    @Test func cancelRemovesTheUpload() async throws {
        let size = 40 * CloudCrypto.chunkSize
        let url = try Self.file(bytes: size)
        defer { try? FileManager.default.removeItem(at: url) }
        let api = FakeAPI()
        api.stopAfterPuts = 2
        let queue = CloudUploadQueue(api: api, keys: Self.keys(), stateURL: nil)
        queue.retryDelay = .seconds(60)
        let local = UUID()
        queue.enqueue(id: local, fileURL: url, meta: Self.meta(bytes: size))
        await Self.waitUntil { queue.job(for: local)?.state == .waiting }
        let cloudId = try #require(queue.job(for: local)?.recordingId)
        await queue.cancel(local)
        #expect(queue.jobs.isEmpty)
        #expect(api.deleted == [cloudId])
        #expect(queue.uploaded[local] == nil)
    }

    @Test func quotaRefusesBeforeStart() async throws {
        let size = 3 * CloudCrypto.chunkSize
        let url = try Self.file(bytes: size)
        defer { try? FileManager.default.removeItem(at: url) }
        let api = FakeAPI()
        api.quotaFree = 1_000_000
        let queue = CloudUploadQueue(api: api, keys: Self.keys(), stateURL: nil)
        let local = UUID()
        queue.enqueue(id: local, fileURL: url, meta: Self.meta(bytes: size))
        await Self.waitUntil { queue.job(for: local)?.state == .failed }
        #expect(queue.job(for: local)?.message?.contains("1 MB") == true)
        #expect(api.puts == 0)
    }

    /// Five parts, so the limit of four is reached and the fifth waits; only two URLs come with
    /// the start, so a batch is fetched while parts are in flight (parallel-cloud-upload 1.2, 2.1).
    @Test func sendsUpToFourPartsAtOnce() async throws {
        let size = 65 * CloudCrypto.chunkSize   // five parts
        let url = try Self.file(bytes: size)
        defer { try? FileManager.default.removeItem(at: url) }
        let api = FakeAPI()
        api.delay = .milliseconds(150)
        api.initialURLs = 2
        let queue = CloudUploadQueue(api: api, keys: Self.keys(), stateURL: nil)
        let local = UUID()
        queue.enqueue(id: local, fileURL: url, meta: Self.meta(bytes: size))
        await Self.waitUntil { queue.uploaded[local] != nil || queue.job(for: local)?.state == .failed }
        #expect(queue.job(for: local)?.message == nil)
        let cloudId = try #require(queue.uploaded[local])
        #expect(api.maxInFlight == CloudUploadQueue.parallelParts)
        #expect(api.partPuts == [1: 1, 2: 1, 3: 1, 4: 1, 5: 1])
        #expect(api.partURLCalls >= 1)
        #expect(Int64(try #require(api.completed[cloudId]).count) == CloudFileLayout(plaintextSize: Int64(size)).ciphertextSize)
    }

    /// Part 3 fails after 1, 2 and 4 finished: the resume sends only the missing parts, and the
    /// object still decrypts to the file (parallel-cloud-upload 2.2).
    @Test func resumesWithGaps() async throws {
        let size = 65 * CloudCrypto.chunkSize + 7   // five parts, the last one short
        let url = try Self.file(bytes: size)
        defer { try? FileManager.default.removeItem(at: url) }
        let api = FakeAPI()
        api.delay = .milliseconds(20)
        api.partDelay = [3: .milliseconds(300)]
        api.failOnce = [3]
        let queue = CloudUploadQueue(api: api, keys: Self.keys(), stateURL: nil)
        queue.retryDelay = .seconds(60)
        let local = UUID()
        let meta = Self.meta(bytes: size)
        queue.enqueue(id: local, fileURL: url, meta: meta)
        await Self.waitUntil { queue.job(for: local)?.state == .waiting }
        let done = Set(try #require(queue.job(for: local)).doneParts.keys)
        #expect(done.isSuperset(of: [1, 2, 4]))
        #expect(!done.contains(3))
        queue.pause()
        queue.resume()
        await Self.waitUntil { queue.uploaded[local] != nil }
        let cloudId = try #require(queue.uploaded[local])
        #expect(api.partPuts == [1: 1, 2: 1, 3: 1, 4: 1, 5: 1])
        let object = try #require(api.completed[cloudId])
        let layout = CloudFileLayout(plaintextSize: Int64(size))
        let file = try Data(contentsOf: url)
        for index in [0, 32, layout.chunkCount - 1] {   // in part 1, part 3 and the last part
            let range = layout.ciphertextRange(ofChunk: index)
            let plain = try CloudCrypto.openChunk(object[Int(range.lowerBound)..<Int(range.upperBound)], index: index,
                                                  isLast: layout.isLast(index), key: meta.key, recordingId: cloudId)
            let expected = layout.plaintextRange(ofChunk: index)
            #expect(plain == file[Int(expected.lowerBound)..<Int(expected.upperBound)])
        }
    }

    /// Cancelling while parts are in flight stops them: nothing is stored after `cancel` returns
    /// (parallel-cloud-upload 2.3).
    @Test func cancelStopsPartsInFlight() async throws {
        let size = 65 * CloudCrypto.chunkSize
        let url = try Self.file(bytes: size)
        defer { try? FileManager.default.removeItem(at: url) }
        let api = FakeAPI()
        api.delay = .milliseconds(400)
        let queue = CloudUploadQueue(api: api, keys: Self.keys(), stateURL: nil)
        let local = UUID()
        queue.enqueue(id: local, fileURL: url, meta: Self.meta(bytes: size))
        await Self.waitUntil { api.lock.withLock { api.inFlight } >= 2 }
        let cloudId = try #require(queue.job(for: local)?.recordingId)
        await queue.cancel(local)
        let puts = api.lock.withLock { api.puts }
        #expect(api.lock.withLock { api.inFlight } == 0)
        try await Task.sleep(for: .milliseconds(600))
        #expect(api.lock.withLock { api.puts } == puts)
        #expect(queue.jobs.isEmpty)
        #expect(queue.uploaded[local] == nil)
        #expect(api.deleted == [cloudId])
    }
}
