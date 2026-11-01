import FernsyShared
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Copies a live MPEG-TS stream into a file (design 2): no decoding. When the connection breaks or
/// delivers nothing for `stallSeconds`, it reconnects with backoff (2, 4, 8 … 30 s) and records
/// the time without data as a gap, as the apps mark theirs.
final class StreamRecorder: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Result {
        var bytes: Int64
        var gaps: [RecordingGap]
        /// The disk refused a write.
        var diskFull: Bool
    }

    static let stallSeconds: TimeInterval = 20
    static let minimumGap: TimeInterval = 2

    private let url: URL
    private let file: URL
    private let lock = NSLock()
    private var session: URLSession!
    private var handle: FileHandle?
    private var task: URLSessionDataTask?
    private var connectedAt = Date()
    private var lastData: Date?
    private var gapStart: Date?
    private var gaps: [RecordingGap] = []
    private var bytes: Int64 = 0
    private var attempt = 0
    private var stopped = false
    private var diskFull = false
    private var watchdog: Task<Void, Never>?
    private let label: String

    /// `bytes` continues a file that a restart interrupted.
    init(url: URL, file: URL, label: String, bytes: Int64 = 0, gaps: [RecordingGap] = []) {
        self.url = url
        self.file = file
        self.label = label
        self.bytes = bytes
        self.gaps = gaps
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Self.stallSeconds
        configuration.timeoutIntervalForResource = 24 * 3600
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    func start() throws {
        if !FileManager.default.fileExists(atPath: file.path) { _ = FileManager.default.createFile(atPath: file.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        lock.withLock {
            self.handle = handle
            // A restart in the middle of a recording: the time it was off is a gap.
            if bytes > 0 { gapStart = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? Date() }
        }
        connect()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.checkStall()
            }
        }
    }

    /// Stops and closes the file; a gap still open runs until now.
    func stop() -> Result {
        watchdog?.cancel()
        return lock.withLock {
            stopped = true
            task?.cancel()
            session.invalidateAndCancel()
            try? handle?.close()
            handle = nil
            closeGap(at: Date())
            return Result(bytes: bytes, gaps: gaps, diskFull: diskFull)
        }
    }

    var progress: (bytes: Int64, gaps: [RecordingGap]) { lock.withLock { (bytes, gaps) } }

    private func connect() {
        lock.withLock {
            guard !stopped else { return }
            connectedAt = Date()
            var request = URLRequest(url: url)
            request.setValue("Fernsy-Server/\(Config.version)", forHTTPHeaderField: "User-Agent")
            task = session.dataTask(with: request)
            task?.resume()
        }
    }

    private func closeGap(at now: Date) {
        guard let start = gapStart else { return }
        let seconds = now.timeIntervalSince(start)
        if seconds >= Self.minimumGap { gaps.append(RecordingGap(at: start, seconds: seconds)) }
        gapStart = nil
    }

    private func checkStall() {
        let stalled = lock.withLock { () -> Bool in
            guard !stopped, task != nil else { return false }
            return Date().timeIntervalSince(lastData.map { max($0, connectedAt) } ?? connectedAt) > Self.stallSeconds
        }
        if stalled {
            Log.warning("\(label): no data for \(Int(Self.stallSeconds)) s, reconnecting")
            lock.withLock { task?.cancel() }
        }
    }

    /// The connection is gone: mark the gap's start and try again after the backoff.
    private func broke() {
        let delay: Double? = lock.withLock {
            guard !stopped else { return nil }
            task = nil
            if gapStart == nil { gapStart = lastData ?? Date() }
            let delay = min(30, pow(2, Double(attempt + 1)))
            attempt += 1
            return delay
        }
        guard let delay else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.connect()
        }
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) {
            completionHandler(.allow)
        } else {
            Log.warning("\(label): provider answered HTTP \(status)")
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.withLock {
            guard !stopped, let handle else { return }
            do {
                try handle.write(contentsOf: data)
            } catch {
                if !diskFull { Log.error("\(label): cannot write: \(error.localizedDescription)") }
                diskFull = true
                return
            }
            let now = Date()
            closeGap(at: now)
            bytes += Int64(data.count)
            lastData = now
            attempt = 0
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if lock.withLock({ stopped }) { return }
        // Only the code: the error's text may name the stream URL, which holds the login.
        Log.warning("\(label): stream ended\(error.map { " (error \(($0 as NSError).code))" } ?? ""), reconnecting")
        broke()
    }
}
