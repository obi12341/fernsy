import Foundation

/// A recording in Fernsy Cloud as the apps list it: the server's id and sizes, and the details
/// decrypted with the account key, or none when this device has no key (locked).
public struct CloudRecordingItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let dataBytes: Int64
    public let completedAt: Date
    /// nil: locked (no key) or damaged details.
    public let meta: CloudRecordingMeta?
    public let isDamaged: Bool

    public init(id: String, dataBytes: Int64, completedAt: Date, meta: CloudRecordingMeta?, isDamaged: Bool = false) {
        self.id = id
        self.dataBytes = dataBytes
        self.completedAt = completedAt
        self.meta = meta
        self.isDamaged = isDamaged
    }

    public var isLocked: Bool { meta == nil && !isDamaged }
    /// Newest first: by recording start, else by upload time.
    public var sortDate: Date { meta?.recordStart ?? completedAt }
}

/// What the library needs from the API (a protocol so tests can stub it).
public protocol CloudRecordingSource: Sendable {
    func recordings() async throws -> [CloudClient.Recording]
    func readURLs(id: String) async throws -> CloudClient.ReadURLs
}

extension CloudClient: CloudRecordingSource {}

/// Merges the server's list with the decrypted details (add-recording-cloud 3.4). The sealed
/// details are cached on disk per recording id, so a list loads with one request once known;
/// they are useless without the key, like everything the server holds.
public final class CloudLibrary: Sendable {
    private let source: CloudRecordingSource
    private let keys: CloudKeyStore
    private let cacheDirectory: URL?
    private let fetch: @Sendable (URL) async throws -> Data

    public init(source: CloudRecordingSource, keys: CloudKeyStore, cacheDirectory: URL? = CloudLibrary.defaultCache,
                fetch: @escaping @Sendable (URL) async throws -> Data = { try await URLSession.shared.data(from: $0).0 }) {
        self.source = source
        self.keys = keys
        self.cacheDirectory = cacheDirectory
        self.fetch = fetch
    }

    public static var defaultCache: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("Fernsy/cloud-meta", isDirectory: true)
    }

    public func items() async throws -> [CloudRecordingItem] {
        let list = try await source.recordings()
        let key = await keys.key()
        var items: [CloudRecordingItem] = []
        await withTaskGroup(of: CloudRecordingItem.self) { group in
            for recording in list {
                group.addTask { await self.item(for: recording, key: key) }
            }
            for await item in group { items.append(item) }
        }
        pruneCache(keeping: Set(list.map(\.id)))
        return items.sorted { $0.sortDate > $1.sortDate }
    }

    private func item(for recording: CloudClient.Recording, key: CloudAccountKey?) async -> CloudRecordingItem {
        func plain(_ damaged: Bool = false) -> CloudRecordingItem {
            CloudRecordingItem(id: recording.id, dataBytes: recording.dataBytes, completedAt: recording.completedAt, meta: nil, isDamaged: damaged)
        }
        guard let key else { return plain() }
        do {
            let sealed = try await sealedMeta(recording.id)
            let meta = try CloudCrypto.openMeta(sealed, accountKey: key, recordingId: recording.id)
            return CloudRecordingItem(id: recording.id, dataBytes: recording.dataBytes, completedAt: recording.completedAt, meta: meta)
        } catch CloudCrypto.Failure.unknownKey {
            return plain()
        } catch CloudCrypto.Failure.damaged, CloudCrypto.Failure.badHeader {
            AppLog.warning(.app, "Fernsy Cloud: details of \(recording.id.prefix(8)) are damaged")
            return plain(true)
        } catch {
            AppLog.warning(.app, "Fernsy Cloud: no details for \(recording.id.prefix(8)): \(error.localizedDescription)")
            return plain()
        }
    }

    private func cacheURL(_ id: String) -> URL? { cacheDirectory?.appendingPathComponent(id + ".meta") }

    private func sealedMeta(_ id: String) async throws -> Data {
        if let url = cacheURL(id), let data = try? Data(contentsOf: url) { return data }
        let urls = try await source.readURLs(id: id)
        let data = try await fetch(urls.metaURL)
        if let url = cacheURL(id), let dir = cacheDirectory {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: url)
        }
        return data
    }

    /// Drops cached details of recordings that are gone (deleted on another device).
    private func pruneCache(keeping ids: Set<String>) {
        guard let dir = cacheDirectory, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where !ids.contains(file.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Forgets a deleted recording's cached details at once.
    public func forget(_ id: String) {
        if let url = cacheURL(id) { try? FileManager.default.removeItem(at: url) }
    }
}
