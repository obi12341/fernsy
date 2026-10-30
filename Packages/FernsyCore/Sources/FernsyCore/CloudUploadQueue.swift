import Foundation
import Observation

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

/// The Mac's upload queue (add-recording-cloud design D): one upload at a time in queue order,
/// parts recomputed from the file and remembered after each one, continuing after quit, sleep
/// or network loss. Finished uploads are remembered as local id → cloud id, so the Recordings
/// section can mark them.
@MainActor
@Observable
public final class CloudUploadQueue {
    public private(set) var jobs: [CloudUploadJob] = []
    /// Local recording id → cloud recording id.
    public private(set) var uploaded: [UUID: String] = [:]
    public private(set) var isRunning = false

    @ObservationIgnored private let api: CloudUploadAPI
    @ObservationIgnored private let keys: CloudKeyStore
    @ObservationIgnored private let stateURL: URL?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var cancelled: Set<UUID> = []
    /// The parts of the running upload, so cancelling that one job stops them at once.
    @ObservationIgnored private var sending: (id: UUID, task: Task<Int64, Error>)?
    @ObservationIgnored public var retryDelay: Duration = .seconds(30)
    /// Parts of one upload in flight at once (parallel-cloud-upload design A): one stream with a
    /// pause after every part reaches only about half of a 200 Mbit/s line.
    public static let parallelParts = 4
    /// Called when an upload finished (the library refreshes).
    @ObservationIgnored public var onUploaded: ((UUID, String) -> Void)?

    private struct Saved: Codable {
        var jobs: [CloudUploadJob]
        var uploaded: [UUID: String]
    }

    public init(api: CloudUploadAPI, keys: CloudKeyStore, stateURL: URL?) {
        self.api = api
        self.keys = keys
        self.stateURL = stateURL
        if let stateURL, let data = try? Data(contentsOf: stateURL), let saved = try? JSONDecoder.cloud.decode(Saved.self, from: data) {
            jobs = saved.jobs.map { var job = $0; if job.state == .uploading { job.state = .queued }; return job }
            uploaded = saved.uploaded
        }
    }

    public static func defaultStateURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Fernsy/cloud-uploads.json")
    }

    public func job(for id: UUID) -> CloudUploadJob? { jobs.first { $0.id == id } }

    /// Queues a finished recording; nothing if it is queued or uploaded already.
    public func enqueue(id: UUID, fileURL: URL, meta: CloudRecordingMeta) {
        guard job(for: id) == nil, uploaded[id] == nil else { return }
        jobs.append(CloudUploadJob(id: id, fileURL: fileURL, meta: meta))
        AppLog.info(.recordings, "Fernsy Cloud: queued \(id.uuidString.prefix(8)) (\(meta.plaintextBytes) bytes)")
        save()
        resume()
    }

    /// Starts working through the queue unless it already runs (launch, network back, retry).
    public func resume() {
        guard worker == nil else { return }
        for index in jobs.indices where jobs[index].state == .failed || jobs[index].state == .waiting {
            jobs[index].state = .queued
            jobs[index].message = nil
        }
        worker = Task { [weak self] in
            await self?.run()
            self?.worker = nil
        }
    }

    /// Stops the parts in flight; jobs stay for the next `resume()` (switch off).
    public func pause() {
        worker?.cancel()
        worker = nil
        isRunning = false
    }

    /// Removes a job and anything of it on the server.
    public func cancel(_ id: UUID) async {
        guard let job = job(for: id) else { return }
        cancelled.insert(id)
        jobs.removeAll { $0.id == id }
        save()
        if let sending, sending.id == id {
            sending.task.cancel()
            _ = await sending.task.result
        }
        if let recordingId = job.recordingId {
            do { try await api.delete(id: recordingId) } catch {
                AppLog.warning(.recordings, "Fernsy Cloud: could not remove the cancelled upload: \(error.localizedDescription)")
            }
        }
        AppLog.info(.recordings, "Fernsy Cloud: upload of \(id.uuidString.prefix(8)) cancelled")
    }

    /// The cloud copy was deleted (on any device): the row loses its cloud mark.
    public func forgetUploaded(cloudId: String) {
        guard let local = uploaded.first(where: { $0.value == cloudId })?.key else { return }
        uploaded[local] = nil
        save()
    }

    /// Keeps only marks whose cloud recording still exists (after a library refresh).
    public func reconcile(existing cloudIds: Set<String>) {
        let stale = uploaded.filter { !cloudIds.contains($0.value) }.map(\.key)
        guard !stale.isEmpty else { return }
        for id in stale { uploaded[id] = nil }
        save()
    }

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        while !Task.isCancelled, let index = jobs.firstIndex(where: { $0.state == .queued }) {
            let id = jobs[index].id
            jobs[index].state = .uploading
            do {
                try await upload(id)
            } catch is CancellationError {
                // Only this job was cancelled: go on with the next one.
                guard Task.isCancelled else { continue }
                update(id) { $0.state = .queued }
                return
            } catch let failure as CloudClient.Failure {
                switch failure {
                case .network, .server:
                    // Comes back by itself: wait, then go on with the same job.
                    update(id) { $0.state = .waiting; $0.message = String(localized: "Waiting for the network", bundle: .module) }
                    AppLog.warning(.recordings, "Fernsy Cloud: upload waits: \(failure)")
                    try? await Task.sleep(for: retryDelay)
                    update(id) { if $0.state == .waiting { $0.state = .queued } }
                case .quota(let needed, let free):
                    update(id) {
                        $0.state = .failed
                        $0.message = String(localized: "Not enough Fernsy Cloud storage: \(Self.bytes(needed)) needed, \(Self.bytes(free)) free.", bundle: .module)
                    }
                case .noSubscription:
                    update(id) { $0.state = .failed; $0.message = String(localized: "Fernsy Cloud needs an active subscription.", bundle: .module) }
                case .accountConflict:
                    update(id) { $0.state = .failed; $0.message = CloudModel.describe(failure) }
                case .notFound:
                    // The server forgot the upload (abandoned after 7 days): start over.
                    update(id) { $0.recordingId = nil; $0.uploadId = nil; $0.doneParts = [:]; $0.metaUploaded = false; $0.state = .queued }
                default:
                    update(id) { $0.state = .failed; $0.message = "\(failure)" }
                }
            } catch {
                update(id) { $0.state = .failed; $0.message = error.localizedDescription }
                AppLog.warning(.recordings, "Fernsy Cloud: upload failed: \(error.localizedDescription)")
            }
            save()
        }
    }

    private func upload(_ id: UUID) async throws {
        guard var job = job(for: id) else { return }
        let fileURL = URL(fileURLWithPath: job.filePath)
        guard FileManager.default.fileExists(atPath: job.filePath) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let accountKey = try await keys.createIfMissing()
        api.use(accountKey)
        if job.recordingId == nil {
            // The details' size does not depend on the id (it is only authenticated).
            let metaSize = try CloudCrypto.sealMeta(job.meta, accountKey: accountKey, recordingId: UUID().uuidString.lowercased()).count
            let upload = try await api.startUpload(dataBytes: job.layout.ciphertextSize, metaBytes: Int64(metaSize), partSize: CloudCrypto.partSize)
            job.recordingId = upload.id
            job.uploadId = upload.uploadId
            update(id) { $0.recordingId = upload.id; $0.uploadId = upload.uploadId }
            save()
            try await putMeta(job, url: upload.metaURL, key: accountKey)
            urls = Dictionary(upload.partURLs.map { ($0.number, $0.url) }, uniquingKeysWith: { a, _ in a })
            urlsFetched = .now
        } else if !job.metaUploaded {
            let fresh = try await api.partURLs(id: job.recordingId!, numbers: [], meta: true)
            if let metaURL = fresh.metaURL { try await putMeta(job, url: metaURL, key: accountKey) }
        }
        guard let recordingId = job.recordingId else { return }
        let started = ContinuousClock.now
        let task = Task { try await self.sendParts(id, fileURL: fileURL, meta: job.meta, recordingId: recordingId) }
        sending = (id, task)
        defer { if sending?.id == id { sending = nil } }
        let sent = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard let finished = self.job(for: id), !cancelled.contains(id) else { return }
        let parts = finished.doneParts.map { CloudClient.CompletedPart(number: $0.key, etag: $0.value) }.sorted { $0.number < $1.number }
        try await api.complete(id: recordingId, parts: parts)
        jobs.removeAll { $0.id == id }
        uploaded[id] = recordingId
        urls = [:]
        save()
        let seconds = max(0.001, (ContinuousClock.now - started) / .seconds(1))
        AppLog.info(.recordings, "Fernsy Cloud: uploaded \(id.uuidString.prefix(8)) as \(recordingId.prefix(8)), "
            + "\(Self.bytes(sent)) in \(String(format: "%.1f", seconds)) s (\(String(format: "%.0f", Double(sent) * 8 / 1_000_000 / seconds)) Mbit/s)")
        onUploaded?(id, recordingId)
    }

    /// Sends the missing parts, up to `parallelParts` at once; each finished part is saved at
    /// once, so a resume skips it even when an earlier one is missing. After a failure the parts
    /// still in flight are cancelled but those that finished are kept. Returns the bytes sent.
    private func sendParts(_ id: UUID, fileURL: URL, meta: CloudRecordingMeta, recordingId: String) async throws -> Int64 {
        let encryptor = try CloudFileEncryptor(url: fileURL, plaintextSize: meta.plaintextBytes, key: meta.key, recordingId: recordingId)
        let layout = encryptor.layout
        var missing = (1...max(1, layout.partCount)).filter { job(for: id)?.doneParts[$0] == nil }[...]
        var sent: Int64 = 0
        var failure: Error?
        await withThrowingTaskGroup(of: (number: Int, etag: String, bytes: Int).self) { group in
            var inFlight = 0
            while true {
                while failure == nil, inFlight < Self.parallelParts, let number = missing.popFirst() {
                    if Task.isCancelled || cancelled.contains(id) { failure = CancellationError(); break }
                    // On the main actor: the encryptor's file handle is not thread-safe.
                    let data: Data
                    do { data = try encryptor.bytes(in: layout.range(ofPart: number)) } catch {
                        failure = error
                        group.cancelAll()
                        break
                    }
                    group.addTask { (number, try await self.putPart(number, of: recordingId, data: data, total: layout.partCount), data.count) }
                    inFlight += 1
                }
                guard let result = await group.nextResult() else { break }
                inFlight -= 1
                switch result {
                case .success(let part):
                    update(id) { $0.doneParts[part.number] = part.etag }
                    save()
                    sent += Int64(part.bytes)
                case .failure(let error):
                    if failure == nil { failure = error; group.cancelAll() }
                }
            }
        }
        if let failure { throw failure }
        try Task.checkCancellation()
        return sent
    }

    /// Signed part URLs of the current upload; renewed after 50 minutes (they last an hour).
    @ObservationIgnored private var urls: [Int: URL] = [:]
    @ObservationIgnored private var urlsFetched = Date.distantPast

    private func putPart(_ number: Int, of recordingId: String, data: Data, total: Int) async throws -> String {
        for attempt in 0..<2 {
            if urls[number] == nil || Date.now.timeIntervalSince(urlsFetched) > 50 * 60 || attempt > 0 {
                let batch = Array(number...min(total, number + CloudClient.partURLBatch - 1))
                let fresh = try await api.partURLs(id: recordingId, numbers: batch, meta: false)
                // Merged, not replaced: other parts in flight may still need their URLs (design B).
                urls.merge(fresh.parts.map { ($0.number, $0.url) }, uniquingKeysWith: { _, new in new })
                urlsFetched = .now
            }
            guard let url = urls[number] else { throw CloudClient.Failure.server(status: 0, code: "no_part_url") }
            do {
                return try await api.put(data, to: url)
            } catch CloudClient.Failure.server(403, _) where attempt == 0 {
                continue
            }
        }
        throw CloudClient.Failure.server(status: 403, code: "expired_url")
    }

    private func putMeta(_ job: CloudUploadJob, url: URL, key: CloudAccountKey) async throws {
        guard let recordingId = job.recordingId else { return }
        _ = try await api.put(try CloudCrypto.sealMeta(job.meta, accountKey: key, recordingId: recordingId), to: url)
        update(job.id) { $0.metaUploaded = true }
        save()
    }

    private func update(_ id: UUID, _ change: (inout CloudUploadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    private func save() {
        guard let stateURL else { return }
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.cloud.encode(Saved(jobs: jobs, uploaded: uploaded)).write(to: stateURL, options: .atomic)
        } catch {
            AppLog.warning(.recordings, "Fernsy Cloud: could not save the upload queue: \(error.localizedDescription)")
        }
    }

    public static func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
}
