import FernsyShared
import Foundation

/// Uploads a finished recording to Fernsy Cloud like the Mac's queue (design 6): the same file
/// format and details, parts remembered after each one so a restart continues, up to four parts
/// at once.
struct Uploader {
    static let parallelParts = 4

    let api: CloudUploadAPI
    let key: CloudAccountKey

    /// Runs the job to the end; `save` is called after every step worth keeping. Returns the
    /// cloud recording id.
    func run(_ job: CloudUploadJob, save: @escaping (CloudUploadJob) -> Void) async throws -> String {
        var job = job
        api.use(key)
        var urls: [Int: URL] = [:]
        if job.recordingId == nil {
            let metaSize = try CloudCrypto.sealMeta(job.meta, accountKey: key, recordingId: UUID().uuidString.lowercased()).count
            let upload = try await api.startUpload(dataBytes: job.layout.ciphertextSize, metaBytes: Int64(metaSize), partSize: CloudCrypto.partSize)
            job.recordingId = upload.id
            job.uploadId = upload.uploadId
            save(job)
            _ = try await api.put(try CloudCrypto.sealMeta(job.meta, accountKey: key, recordingId: upload.id), to: upload.metaURL)
            job.metaUploaded = true
            save(job)
            urls = Dictionary(upload.partURLs.map { ($0.number, $0.url) }, uniquingKeysWith: { a, _ in a })
        } else if !job.metaUploaded, let id = job.recordingId {
            if let metaURL = try await api.partURLs(id: id, numbers: [], meta: true).metaURL {
                _ = try await api.put(try CloudCrypto.sealMeta(job.meta, accountKey: key, recordingId: id), to: metaURL)
            }
            job.metaUploaded = true
            save(job)
        }
        let recordingId = job.recordingId!
        let encryptor = try CloudFileEncryptor(url: URL(fileURLWithPath: job.filePath), plaintextSize: job.meta.plaintextBytes,
                                               key: job.meta.key, recordingId: recordingId)
        let layout = encryptor.layout
        var missing = (1...max(1, layout.partCount)).filter { job.doneParts[$0] == nil }[...]
        while !missing.isEmpty {
            let batch = Array(missing.prefix(Self.parallelParts))
            missing = missing.dropFirst(batch.count)
            if batch.contains(where: { urls[$0] == nil }) {
                let fresh = try await api.partURLs(id: recordingId, numbers: Array(batch.first!...min(layout.partCount, batch.first! + CloudClient.partURLBatch - 1)), meta: false)
                urls.merge(fresh.parts.map { ($0.number, $0.url) }, uniquingKeysWith: { _, new in new })
            }
            // Read serially (the encryptor's file handle is not thread-safe), send in parallel.
            let parts = try batch.map { ($0, try encryptor.bytes(in: layout.range(ofPart: $0))) }
            let etags = try await withThrowingTaskGroup(of: (Int, String).self) { group in
                for (number, data) in parts {
                    guard let url = urls[number] else { throw CloudClient.Failure.server(status: 0, code: "no_part_url") }
                    group.addTask { (number, try await api.put(data, to: url)) }
                }
                return try await group.reduce(into: [Int: String]()) { $0[$1.0] = $1.1 }
            }
            job.doneParts.merge(etags, uniquingKeysWith: { _, new in new })
            save(job)
        }
        let completed = job.doneParts.map { CloudClient.CompletedPart(number: $0.key, etag: $0.value) }.sorted { $0.number < $1.number }
        try await api.complete(id: recordingId, parts: completed)
        return recordingId
    }
}
