import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What the upload queue needs from the API (a protocol so tests can stub it).
public protocol CloudUploadAPI: Sendable {
    func startUpload(dataBytes: Int64, metaBytes: Int64, partSize: Int) async throws -> CloudClient.Upload
    func partURLs(id: String, numbers: [Int], meta: Bool) async throws -> (parts: [CloudClient.PartURL], metaURL: URL?)
    func complete(id: String, parts: [CloudClient.CompletedPart]) async throws
    func delete(id: String) async throws
    /// PUTs `data` to a signed storage URL; returns the ETag.
    func put(_ data: Data, to url: URL) async throws -> String
    /// Requests from now on go to this key's account.
    func use(_ key: CloudAccountKey)
}

public extension CloudUploadAPI {
    func use(_ key: CloudAccountKey) {}
}

extension CloudClient: CloudUploadAPI {
    public func put(_ data: Data, to url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 120
        let response: URLResponse
        do {
            (_, response) = try await URLSession.shared.upload(for: request, from: data)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        let http = response as? HTTPURLResponse
        guard let http, (200..<300).contains(http.statusCode) else {
            throw http?.statusCode == 403 ? Failure.server(status: 403, code: "expired_url") : Failure.server(status: http?.statusCode ?? 0, code: "put_failed")
        }
        return http.value(forHTTPHeaderField: "ETag") ?? ""
    }
}

/// One recording to upload, with everything needed to continue after a restart (design D):
/// the plaintext file, its details, and the server's upload with the parts already stored.
public struct CloudUploadJob: Codable, Identifiable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case queued, uploading, waiting, failed }

    /// The local recording's id.
    public let id: UUID
    public var filePath: String
    public var meta: CloudRecordingMeta
    public var state: State = .queued
    public var message: String?
    public var recordingId: String?
    public var uploadId: String?
    public var metaUploaded = false
    public var doneParts: [Int: String] = [:]

    public init(id: UUID, fileURL: URL, meta: CloudRecordingMeta) {
        self.id = id
        self.filePath = fileURL.path
        self.meta = meta
    }

    public var layout: CloudFileLayout { CloudFileLayout(plaintextSize: meta.plaintextBytes) }
    public var progress: Double {
        let total = layout.partCount
        return total == 0 ? 0 : Double(doneParts.count) / Double(total)
    }
}
