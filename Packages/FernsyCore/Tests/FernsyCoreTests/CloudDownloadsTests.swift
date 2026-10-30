import Foundation
import Testing
@testable import FernsyCore

/// Downloads on iPad and iPhone (offline-recording-downloads 1.1, 1.2): queue, space check,
/// cancel and remove, the index after a relaunch, backup exclusion, the size and header check,
/// resume data and the expired URL.
@MainActor
@Suite(.serialized)
struct CloudDownloadsTests {
    /// Stands in for the background session; the test drives its events.
    final class FakeTransfer: CloudDownloadTransfer {
        var onEvent: ((CloudDownloadEvent) -> Void)?
        var started: [(id: String, url: URL, resumeData: Data?)] = []
        var cancelled: [String] = []
        var system: Set<String> = []
        func start(id: String, url: URL, resumeData: Data?) { started.append((id, url, resumeData)); system.insert(id) }
        func cancel(id: String) { cancelled.append(id); system.remove(id) }
        func running() async -> Set<String> { system }
    }

    /// A small recording sealed as in the cloud: its data object, details and list item.
    struct Fixture {
        let id: String
        let key = CloudAccountKey()
        let meta: CloudRecordingMeta
        let data: Data
        let sealedMeta: Data
        var item: CloudRecordingItem { CloudRecordingItem(id: id, dataBytes: Int64(data.count), completedAt: .now, meta: meta) }

        init(id: String = UUID().uuidString.lowercased(), bytes: Int = 3 * CloudCrypto.chunkSize + 11) throws {
            self.id = id
            let plain = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID()).ts")
            try Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0 &* 7) }).write(to: plain)
            defer { try? FileManager.default.removeItem(at: plain) }
            meta = CloudRecordingMeta(title: "Tatort", channel: "Das Erste", showStart: nil, showEnd: nil, recordStart: .now, recordEnd: .now,
                                      plaintextBytes: Int64(bytes), fileKey: CloudCrypto.newFileKey().withUnsafeBytes { Data($0) })
            let encryptor = try CloudFileEncryptor(url: plain, plaintextSize: Int64(bytes), key: meta.key, recordingId: id)
            data = try encryptor.bytes(in: 0..<encryptor.layout.ciphertextSize)
            sealedMeta = try CloudCrypto.sealMeta(meta, accountKey: key, recordingId: id)
        }
    }

    final class Counter: @unchecked Sendable {
        let lock = NSLock()
        var urlCalls: [String] = []
        func add(_ id: String) { lock.withLock { urlCalls.append(id) } }
        var count: Int { lock.withLock { urlCalls.count } }
    }

    static func store(_ dir: URL, _ transfer: FakeTransfer, _ fixtures: [Fixture], free: Int64? = nil, counter: Counter = Counter()) -> CloudDownloads {
        let metas = Dictionary(uniqueKeysWithValues: fixtures.map { ($0.id, $0.sealedMeta) })
        let key = fixtures.first?.key
        return CloudDownloads(directory: dir, transfer: transfer,
                              readURLs: { id in
                                  counter.add(id)
                                  return CloudClient.ReadURLs(dataURL: URL(string: "https://r2.test/\(id).data?n=\(counter.count)")!,
                                                              metaURL: URL(string: "https://r2.test/\(id).meta")!, expiresAt: .now)
                              },
                              fetch: { url in
                                  let id = url.lastPathComponent.replacingOccurrences(of: ".meta", with: "")
                                  guard let data = metas[id] else { throw URLError(.fileDoesNotExist) }
                                  return data
                              },
                              freeSpace: { free },
                              key: { key })
    }

    static func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("downloads-\(UUID())", isDirectory: true) }

    static func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// The transfer's file as the session would leave it in staging.
    static func staged(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("staged-\(UUID()).data")
        try data.write(to: url)
        return url
    }

    @Test func downloadsOneAtATimeAndOpensItsDetails() async throws {
        let dir = Self.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try Fixture(), b = try Fixture()
        let transfer = FakeTransfer()
        let store = Self.store(dir, transfer, [a, b])
        try store.add(a.item)
        try store.add(b.item)
        await Self.waitUntil { transfer.started.count == 1 }
        #expect(transfer.started.map(\.id) == [a.id])
        #expect(store.download(for: b.id)?.state == .waiting)

        transfer.onEvent?(.progress(id: a.id, written: Int64(a.data.count / 2), expected: Int64(a.data.count)))
        #expect(abs((store.download(for: a.id)?.progress ?? 0) - 0.5) < 0.01)
        transfer.onEvent?(.finished(id: a.id, file: try Self.staged(a.data)))
        #expect(store.isDownloaded(a.id))
        #expect(try Data(contentsOf: store.dataURL(a.id)) == a.data)
        await Self.waitUntil { transfer.started.count == 2 }
        #expect(transfer.started.last?.id == b.id)
        await Self.waitUntil { !store.items.isEmpty }
        #expect(store.items.first?.meta?.title == "Tatort")
        #expect(store.usedBytes == Int64(a.data.count))

        // Not in backups.
        let values = try store.dataURL(a.id).resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        // The index survives a relaunch.
        let again = Self.store(dir, FakeTransfer(), [a, b])
        #expect(again.isDownloaded(a.id))
        await again.loadItems()
        #expect(again.items.map(\.id) == [a.id])
    }

    @Test func refusesWithoutSpace() async throws {
        let dir = Self.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try Fixture()
        let store = Self.store(dir, FakeTransfer(), [a], free: CloudDownloads.spaceMargin + 10)
        #expect(throws: CloudDownloads.NotEnoughSpace(needed: Int64(a.data.count), free: CloudDownloads.spaceMargin + 10)) { try store.add(a.item) }
        #expect(store.downloads.isEmpty)
    }

    @Test func cancelAndRemoveCleanUp() async throws {
        let dir = Self.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try Fixture(), b = try Fixture()
        let transfer = FakeTransfer()
        let store = Self.store(dir, transfer, [a, b])
        try store.add(a.item)
        await Self.waitUntil { transfer.started.count == 1 }
        store.remove(a.id)   // cancel while it runs
        #expect(transfer.cancelled == [a.id])
        #expect(store.downloads.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(a.id).meta").path))

        try store.add(b.item)
        await Self.waitUntil { transfer.started.count == 2 }
        transfer.onEvent?(.finished(id: b.id, file: try Self.staged(b.data)))
        #expect(store.isDownloaded(b.id))
        store.remove(b.id)   // "Remove Download"
        #expect(!FileManager.default.fileExists(atPath: store.dataURL(b.id).path))
        #expect(store.usedBytes == 0)
    }

    @Test func wrongSizeFailsAndResumeDataIsUsed() async throws {
        let dir = Self.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try Fixture()
        let transfer = FakeTransfer()
        let store = Self.store(dir, transfer, [a])
        try store.add(a.item)
        await Self.waitUntil { transfer.started.count == 1 }
        transfer.onEvent?(.finished(id: a.id, file: try Self.staged(a.data.prefix(100))))
        #expect(store.download(for: a.id)?.state == .failed)
        #expect(!FileManager.default.fileExists(atPath: store.dataURL(a.id).path))

        // Network lost: resume data kept, and the next start continues with it.
        await store.resume()
        await Self.waitUntil { transfer.started.count == 2 }
        let partial = Data("resume".utf8)
        transfer.system.remove(a.id)
        transfer.onEvent?(.failed(id: a.id, message: "offline", status: nil, resumeData: partial))
        #expect(store.download(for: a.id)?.resumeData == partial)
        await store.resume()
        await Self.waitUntil { transfer.started.count == 3 }
        #expect(transfer.started.last?.resumeData == partial)
    }

    @Test func expiredURLStartsOverWithAFreshOne() async throws {
        let dir = Self.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try Fixture()
        let transfer = FakeTransfer()
        let counter = Counter()
        let store = Self.store(dir, transfer, [a], counter: counter)
        try store.add(a.item)
        await Self.waitUntil { transfer.started.count == 1 }
        transfer.system.remove(a.id)
        transfer.onEvent?(.failed(id: a.id, message: "HTTP 403", status: 403, resumeData: nil))
        await Self.waitUntil { transfer.started.count == 2 }
        #expect(counter.count == 2)
        #expect(transfer.started[1].url != transfer.started[0].url)
        #expect(transfer.started[1].resumeData == nil)
    }

    @Test func keepOnlyRemovesWhatTheCloudLost() async throws {
        let dir = Self.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try Fixture(), b = try Fixture()
        let transfer = FakeTransfer()
        let store = Self.store(dir, transfer, [a, b])
        for fixture in [a, b] {
            try store.add(fixture.item)
            await Self.waitUntil { transfer.started.contains { $0.id == fixture.id } }
            transfer.onEvent?(.finished(id: fixture.id, file: try Self.staged(fixture.data)))
        }
        store.keepOnly([b.id])
        #expect(store.downloads.map(\.id) == [b.id])
    }

    /// A plain session in place of the background one, for the live test (a background session
    /// needs an app).
    final class ForegroundTransfer: CloudDownloadTransfer {
        var onEvent: ((CloudDownloadEvent) -> Void)?
        func start(id: String, url: URL, resumeData: Data?) {
            Task {
                do {
                    let (file, response) = try await URLSession.shared.download(from: url)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let target = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(id).data")
                    try? FileManager.default.removeItem(at: target)
                    try FileManager.default.moveItem(at: file, to: target)
                    onEvent?(status == 200 ? .finished(id: id, file: target) : .failed(id: id, message: "HTTP \(status)", status: status, resumeData: nil))
                } catch {
                    onEvent?(.failed(id: id, message: error.localizedDescription, status: nil, resumeData: nil))
                }
            }
        }
        func cancel(id: String) {}
        func running() async -> Set<String> { [] }
    }

    static let liveEnv = ProcessInfo.processInfo.environment

    /// The UI-test fixture from the dev worker: stored with the cloud object's exact size, and its
    /// details open with the test key.
    @Test(.enabled(if: liveEnv["IPTV_CLOUD"] != nil && liveEnv["IPTV_CLOUDTOKEN"] != nil && liveEnv["IPTV_CLOUDKEY"] != nil && liveEnv["FERNSY_CLOUD_FIXTURE_ID"] != nil))
    func downloadsTheFixtureFromTheDevServer() async throws {
        let client = CloudClient(baseURL: URL(string: Self.liveEnv["IPTV_CLOUD"]!)!, credential: .dev(Self.liveEnv["IPTV_CLOUDTOKEN"]!))
        let key = try JSONDecoder().decode(CloudAccountKey.self, from: try #require(Data(base64Encoded: Self.liveEnv["IPTV_CLOUDKEY"]!)))
        let id = Self.liveEnv["FERNSY_CLOUD_FIXTURE_ID"]!
        let recording = try #require(try await client.recordings().first { $0.id == id })
        let dir = Self.directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CloudDownloads(directory: dir, transfer: ForegroundTransfer(), readURLs: { try await client.readURLs(id: $0) }, key: { key })
        try store.add(CloudRecordingItem(id: id, dataBytes: recording.dataBytes, completedAt: recording.completedAt, meta: nil))
        for _ in 0..<600 where !store.isDownloaded(id) && store.download(for: id)?.state != .failed { try await Task.sleep(for: .milliseconds(100)) }
        #expect(store.download(for: id)?.message == nil)
        #expect(store.isDownloaded(id))
        let size = try FileManager.default.attributesOfItem(atPath: store.dataURL(id).path)[.size] as? Int64
        #expect(size == recording.dataBytes)
        await store.loadItems()
        #expect(store.items.first?.meta?.title == "Cloud Fixture")
    }
}

