import Foundation
import Testing
@testable import FernsyCore

/// Cloud recordings as listed (add-recording-cloud 3.4): locked without a key, full details with it.
struct CloudLibraryTests {
    final class Server: CloudRecordingSource, @unchecked Sendable {
        var list: [CloudClient.Recording] = []
        var metas: [String: Data] = [:]
        func recordings() async throws -> [CloudClient.Recording] { list }
        func readURLs(id: String) async throws -> CloudClient.ReadURLs {
            CloudClient.ReadURLs(dataURL: URL(string: "https://r2.test/\(id).data")!, metaURL: URL(string: "https://r2.test/\(id).meta")!, expiresAt: .now)
        }
    }

    static func meta(_ title: String, start: TimeInterval) -> CloudRecordingMeta {
        CloudRecordingMeta(title: title, channel: "Das Erste", showStart: nil, showEnd: nil, recordStart: Date(timeIntervalSince1970: start),
                           recordEnd: Date(timeIntervalSince1970: start + 3600), plaintextBytes: 10, fileKey: Data(count: 32))
    }

    static func library(_ server: Server, key: CloudAccountKey?) -> CloudLibrary {
        let keys = CloudKeyStore(backing: nil, loadLocal: { key }, saveLocal: { _ in })
        return CloudLibrary(source: server, keys: keys, cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("cloudlib-\(UUID())")) { url in
            let id = url.deletingPathExtension().lastPathComponent
            guard let data = server.metas[id] else { throw URLError(.fileDoesNotExist) }
            return data
        }
    }

    @Test func lockedWithoutKeyFullWithKey() async throws {
        let key = CloudAccountKey()
        let server = Server()
        server.list = [.init(id: "a", dataBytes: 100, metaBytes: 10, completedAt: .now), .init(id: "b", dataBytes: 200, metaBytes: 10, completedAt: .now)]
        server.metas["a"] = try CloudCrypto.sealMeta(Self.meta("Older", start: 1000), accountKey: key, recordingId: "a")
        server.metas["b"] = try CloudCrypto.sealMeta(Self.meta("Newer", start: 5000), accountKey: key, recordingId: "b")

        let locked = try await Self.library(server, key: nil).items()
        #expect(locked.count == 2)
        #expect(locked.allSatisfy { $0.isLocked })

        let items = try await Self.library(server, key: key).items()
        #expect(items.map { $0.meta?.title } == ["Newer", "Older"])

        // Another key (e.g. a second Apple ID) reads as locked, swapped details as damaged.
        let other = try await Self.library(server, key: CloudAccountKey()).items()
        #expect(other.allSatisfy { $0.isLocked })
        server.metas["a"] = server.metas["b"]
        let damaged = try await Self.library(server, key: key).items()
        #expect(damaged.first { $0.id == "a" }?.isDamaged == true)
    }
}
