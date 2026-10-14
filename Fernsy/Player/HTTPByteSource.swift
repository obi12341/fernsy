import Foundation

/// Streams an HTTP resource through URLSession and exposes blocking read/seek
/// calls for FFmpeg's custom I/O.
///
/// URLSession is used instead of FFmpeg's own HTTP stack because the system
/// network stack is what the Xtream servers accept (plain curl-style clients get
/// dropped), and it gives us redirects, proxies and keep-alive handling for free.
final class HTTPByteSource: NSObject, URLSessionDataDelegate {
    enum SourceError: LocalizedError {
        case http(Int)
        case timeout
        case cancelled

        var errorDescription: String? {
            switch self {
            case .http(let code): return String(localized: "Server antwortet mit HTTP \(code)")
            case .timeout: return String(localized: "Zeitüberschreitung beim Verbinden")
            case .cancelled: return String(localized: "Abgebrochen")
            }
        }
    }

    let url: URL
    let isLive: Bool

    private let cond = NSCondition()
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var taskGeneration = 0

    // Buffered bytes: buffer[0] is at absolute offset `bufferBase`; the next byte
    // handed to FFmpeg is buffer[readIndex].
    private var buffer = Data()
    private var bufferBase: Int64 = 0
    private var readIndex = 0

    private var responseReceived = false
    private var finished = false
    private var failure: Error?
    private var cancelled = false
    private var suspended = false

    private(set) var contentLength: Int64 = -1
    private(set) var supportsRanges = false
    /// URL after redirects and MIME type of the first response.
    private(set) var finalURL: URL?
    private(set) var mimeType: String?
    /// Sees every byte handed to FFmpeg, in order (used by TSAudioTap). Demux thread only.
    var tap: ((UnsafeBufferPointer<UInt8>) -> Void)?
    /// Live: called (demux thread, inside `read`) when the reader reaches the first byte of
    /// a reconnected stream, before those bytes are handed out. The argument is that byte's offset.
    var onRejoin: ((Int64) -> Void)?

    // Live reconnect: a dropped or stalled connection is replaced in place and its bytes are
    // appended to the same buffer, so FFmpeg and the decoders never notice beyond a short gap.
    private var streaming = false
    private var reconnecting = false
    private var reconnectAttempts = 0
    private var incidentAttempts = 0
    /// Where the load balancer sent the current connection. Edge servers stamp the same
    /// channel with different clocks, so reconnecting to the same edge keeps timestamps
    /// continuous (and duplicates detectable).
    private var edgeURL: URL?
    private var reconnectStartedAt = Date()
    private var connectionStart: Int64 = 0
    private var connectedAt = Date()
    private var lastDataAt = Date()
    /// Offsets where reconnected data begins and the reader has not arrived yet.
    private var junctions: [Int64] = []
    private var watchdog: DispatchSourceTimer?
    private let watchdogQueue = DispatchQueue(label: "player.http.watchdog")
    private let stallTimeout: TimeInterval = 4
    /// Reconnect when the player has less than this left and nothing arrives.
    private let lowPlaybackAhead: Double = 4
    /// Reconnect regardless of the player's buffer.
    private let hardStallTimeout: TimeInterval = 30
    private var playbackAhead: Double = 0
    private var requestStartedAt = Date()
    private var net = NetStats()
    private let maxReconnectAttempts = 8

    // Bitrate measurement
    private var bytesReceivedTotal: Int64 = 0

    private let highWater = 24 << 20
    private let lowWater = 8 << 20
    private let keepBehind = 1 << 20
    private let readTimeout: TimeInterval

    init(url: URL, isLive: Bool) {
        self.url = url
        self.isLive = isLive
        self.readTimeout = isLive ? 12 : 30
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = readTimeout
        config.timeoutIntervalForResource = .infinity
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpShouldUsePipelining = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }

    struct NetStats {
        /// Live connections replaced in place (each incident counts once, however many attempts).
        var reconnects = 0
        var lastReconnectReason: String?
        var lastReconnectAt: Date?
        var isReconnecting = false
        /// Received but not yet handed to FFmpeg.
        var unreadBytes = 0
        /// Request to response headers of the latest connection.
        var connectTime: TimeInterval = 0
    }

    var netStats: NetStats {
        cond.lock(); defer { cond.unlock() }
        var result = net
        result.isReconnecting = reconnecting
        result.unreadBytes = buffer.count - readIndex
        return result
    }

    var totalBytesReceived: Int64 {
        cond.lock(); defer { cond.unlock() }
        return bytesReceivedTotal
    }

    var isCancelled: Bool {
        cond.lock(); defer { cond.unlock() }
        return cancelled
    }

    // MARK: Lifecycle

    /// Connects and waits for the response headers. Retries a few times because
    /// single-connection accounts can briefly reject us while the previous stream
    /// is still being torn down on the server.
    func open() throws {
        var lastError: Error = SourceError.timeout
        for attempt in 0..<5 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.4 * Double(attempt)) }
            do {
                try connect(at: 0)
                if isLive { startStreaming() }
                return
            } catch SourceError.cancelled {
                throw SourceError.cancelled
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func cancel() {
        cond.lock()
        cancelled = true
        task?.cancel()
        task = nil
        watchdog?.cancel()
        watchdog = nil
        cond.broadcast()
        cond.unlock()
        session.invalidateAndCancel()
    }

    #if DEBUG
    /// Test hooks: kill the connection outright, or silently stop receiving (a stalled socket).
    func debugDropConnection() {
        cond.lock(); defer { cond.unlock() }
        task?.cancel()
    }

    func debugStallConnection() {
        cond.lock(); defer { cond.unlock() }
        task?.suspend()
    }
    #endif

    // MARK: FFmpeg callbacks

    func read(into ptr: UnsafeMutablePointer<UInt8>, size: Int) -> Int32 {
        cond.lock()

        // Live: the watchdog reconnects stalls and gives up after a few attempts, so the
        // read deadline is only a backstop.
        let timeout = streaming ? 60 : readTimeout
        var deadline = Date().addingTimeInterval(timeout)
        var available = buffer.count - readIndex
        while available == 0 && !finished && failure == nil && !cancelled {
            if !cond.wait(until: deadline) {
                if Date() >= deadline {
                    failure = SourceError.timeout
                    break
                }
            }
            let now = buffer.count - readIndex
            if now > available { deadline = Date().addingTimeInterval(timeout) }
            available = now
        }

        if cancelled {
            cond.unlock()
            return Int32(ffs_error_exit())
        }
        guard available > 0 else {
            let ended = finished
            cond.unlock()
            return Int32(ended ? ffs_error_eof() : ffs_error_eio())
        }
        var n = min(size, available)
        var reachedJunction: Int64?
        let position = bufferBase + Int64(readIndex)
        if let junction = junctions.first {
            if position >= junction {
                junctions.removeFirst()
                reachedJunction = junction
            } else {
                n = min(n, Int(junction - position))
            }
        }
        buffer.withUnsafeBytes { raw in
            let src = raw.baseAddress!.advanced(by: readIndex)
            ptr.update(from: src.assumingMemoryBound(to: UInt8.self), count: n)
        }
        readIndex += n
        compactIfNeeded()
        resumeIfNeeded()
        cond.unlock()

        // Callbacks run outside `cond`: they take the session lock, and the session reads
        // source stats while holding it.
        if let reachedJunction { onRejoin?(reachedJunction) }
        tap?(UnsafeBufferPointer(start: ptr, count: n))
        return Int32(n)
    }

    /// Live: seconds of media the player still has queued, reported by the session. A gap in
    /// delivery only counts as a stall once this runs low, because some channels arrive in
    /// segment-sized bursts with several seconds of silence in between.
    func reportPlaybackAhead(_ seconds: Double) {
        cond.lock()
        playbackAhead = seconds
        cond.unlock()
    }

    func seek(offset: Int64, whence: Int32) -> Int64 {
        if whence & Int32(ffs_avseek_size()) != 0 {
            return contentLength >= 0 ? contentLength : -1
        }
        if isLive { return -1 }

        cond.lock()
        let current = bufferBase + Int64(readIndex)
        let mode = whence & ~Int32(ffs_avseek_force())
        let target: Int64
        switch mode {
        case SEEK_SET: target = offset
        case SEEK_CUR: target = current + offset
        case SEEK_END:
            guard contentLength >= 0 else { cond.unlock(); return -1 }
            target = contentLength + offset
        default:
            cond.unlock(); return -1
        }
        if target < 0 { cond.unlock(); return -1 }

        // Inside what we already have (including the retained history)?
        let bufferEnd = bufferBase + Int64(buffer.count)
        if target >= bufferBase && target <= bufferEnd {
            readIndex = Int(target - bufferBase)
            cond.unlock()
            return target
        }

        // Slightly ahead of the download: wait instead of reconnecting.
        if target > bufferEnd && target - bufferEnd < 2 << 20 && !finished && failure == nil {
            let deadline = Date().addingTimeInterval(readTimeout)
            while bufferBase + Int64(buffer.count) < target && !finished && failure == nil && !cancelled {
                if suspended { task?.resume(); suspended = false }
                if !cond.wait(until: deadline) { break }
            }
            if target <= bufferBase + Int64(buffer.count) {
                readIndex = Int(target - bufferBase)
                cond.unlock()
                return target
            }
        }

        let canRange = supportsRanges
        cond.unlock()
        guard canRange else { return -1 }

        for attempt in 0..<4 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.3 * Double(attempt)) }
            do {
                try connect(at: target)
                return target
            } catch SourceError.cancelled {
                return -1
            } catch {
                if !supportsRanges { return -1 }
            }
        }
        return -1
    }

    // MARK: Internals

    private func connect(at offset: Int64) throws {
        cond.lock()
        if cancelled { cond.unlock(); throw SourceError.cancelled }
        task?.cancel()
        taskGeneration += 1
        streaming = false
        reconnecting = false
        reconnectAttempts = 0
        junctions = []
        buffer = Data()
        bufferBase = offset
        readIndex = 0
        responseReceived = false
        finished = false
        failure = nil
        suspended = false

        var request = URLRequest(url: url)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        let newTask = session.dataTask(with: request)
        newTask.taskDescription = String(taskGeneration)
        task = newTask
        requestStartedAt = Date()
        newTask.resume()

        let deadline = Date().addingTimeInterval(15)
        while !responseReceived && failure == nil && !cancelled {
            if !cond.wait(until: deadline) {
                if Date() >= deadline { break }
            }
        }
        defer { cond.unlock() }
        if cancelled { throw SourceError.cancelled }
        if let failure { throw failure }
        if !responseReceived {
            task?.cancel()
            task = nil
            throw SourceError.timeout
        }
    }

    // MARK: Live reconnect

    private func startStreaming() {
        cond.lock()
        streaming = true
        lastDataAt = Date()
        connectedAt = Date()
        connectionStart = bufferBase
        cond.unlock()
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + 1, repeating: 0.5)
        timer.setEventHandler { [weak self] in self?.checkStall() }
        cond.lock()
        watchdog?.cancel()
        watchdog = timer
        cond.unlock()
        timer.resume()
    }

    private func checkStall() {
        cond.lock()
        defer { cond.unlock() }
        guard streaming, !cancelled, failure == nil else { return }
        let now = Date()
        if reconnecting {
            // A reconnect whose response does not arrive is retried like a failed one.
            if task != nil && now.timeIntervalSince(reconnectStartedAt) > 6 {
                liveReconnect(reason: String(localized: "keine Antwort"))
            }
        } else if !suspended {
            let idle = now.timeIntervalSince(lastDataAt)
            if idle > hardStallTimeout || (idle > stallTimeout && playbackAhead < lowPlaybackAhead) {
                liveReconnect(reason: String(format: String(localized: "keine Daten seit %.0f s, %.1f s Vorrat"), idle, playbackAhead))
            }
        }
    }

    /// Replaces the current connection; the caller holds `cond`.
    private func liveReconnect(reason: String) {
        task?.cancel()
        task = nil
        taskGeneration += 1
        suspended = false
        guard reconnectAttempts < maxReconnectAttempts else {
            #if DEBUG
            debugLog("[http] giving up after \(reconnectAttempts) reconnects (\(reason))")
            #endif
            failure = SourceError.timeout
            cond.broadcast()
            return
        }
        reconnectAttempts += 1
        if !reconnecting {
            reconnecting = true
            incidentAttempts = 0
            net.reconnects += 1
            net.lastReconnectReason = reason
            net.lastReconnectAt = Date()
            // A connection cut mid-packet leaves a partial TS packet; dropping it (when not yet
            // read) keeps the demuxer aligned at the junction.
            let end = bufferBase + Int64(buffer.count)
            let partial = Int((end - connectionStart) % 188)
            if partial > 0 && buffer.count - partial >= readIndex {
                buffer.removeLast(partial)
            }
            let junction = bufferBase + Int64(buffer.count)
            if junctions.last != junction { junctions.append(junction) }
            connectionStart = junction
        }
        incidentAttempts += 1
        #if DEBUG
        debugLog("[http] live reconnect #\(reconnectAttempts): \(reason), \(String(format: "%.1f", Double(buffer.count - readIndex) / 1e6)) MB still buffered")
        #endif
        let generation = taskGeneration
        // First try the same edge; if its token or slot is gone, go through the load balancer.
        let target = incidentAttempts == 1 ? (edgeURL ?? url) : url
        // The first retry is quick; later ones give single-connection servers time to
        // release the old slot.
        let delay = reconnectAttempts == 1 ? 0.2 : 0.5 * Double(reconnectAttempts)
        reconnectStartedAt = Date().addingTimeInterval(delay)
        watchdogQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.cond.lock()
            defer { self.cond.unlock() }
            guard !self.cancelled, self.taskGeneration == generation, self.failure == nil else { return }
            var request = URLRequest(url: target)
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let newTask = self.session.dataTask(with: request)
            newTask.taskDescription = String(generation)
            self.task = newTask
            self.reconnectStartedAt = Date()
            self.requestStartedAt = Date()
            newTask.resume()
        }
    }

    private func compactIfNeeded() {
        guard readIndex > 8 << 20 else { return }
        let drop = readIndex - keepBehind
        buffer.removeSubrange(0..<drop)
        bufferBase += Int64(drop)
        readIndex -= drop
    }

    private func resumeIfNeeded() {
        if suspended && buffer.count - readIndex < lowWater {
            suspended = false
            task?.resume()
        }
    }

    private func isCurrent(_ task: URLSessionTask) -> Bool {
        task.taskDescription == String(taskGeneration)
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        cond.lock()
        defer { cond.broadcast(); cond.unlock() }
        guard isCurrent(dataTask) else {
            completionHandler(.cancel)
            return
        }
        if reconnecting {
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 200
            let target = http?.url?.absoluteString.lowercased() ?? ""
            if target.contains("stream_offline") || target.contains("offline.mp4") {
                // The channel went offline: hand over to a full restart, which reports it.
                failure = SourceError.http(status)
                completionHandler(.cancel)
            } else if (200..<300).contains(status) {
                reconnecting = false
                if let edge = http?.url { edgeURL = edge }
                net.connectTime = Date().timeIntervalSince(requestStartedAt)
                connectedAt = Date()
                lastDataAt = Date()
                #if DEBUG
                debugLog("[http] reconnected (HTTP \(status)) via \(http?.url?.host ?? "?")\(incidentAttempts == 1 ? " (same edge)" : " (load balancer)")")
                #endif
                completionHandler(.allow)
            } else {
                completionHandler(.cancel)
                liveReconnect(reason: "HTTP \(status)")
            }
            return
        }
        guard let http = response as? HTTPURLResponse else {
            responseReceived = true
            completionHandler(.allow)
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            failure = SourceError.http(http.statusCode)
            completionHandler(.cancel)
            return
        }
        if http.statusCode == 206 {
            supportsRanges = true
            // Content-Range: bytes start-end/total
            if let range = http.value(forHTTPHeaderField: "Content-Range"),
               let total = range.split(separator: "/").last, let length = Int64(total) {
                contentLength = length
            }
        } else {
            if bufferBase > 0 {
                // Server ignored the Range header and would restart from zero.
                supportsRanges = false
                failure = SourceError.http(http.statusCode)
                completionHandler(.cancel)
                return
            }
            if http.expectedContentLength > 0 { contentLength = http.expectedContentLength }
            if http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes" { supportsRanges = true }
        }
        net.connectTime = Date().timeIntervalSince(requestStartedAt)
        edgeURL = http.url
        if finalURL == nil {
            finalURL = http.url
            mimeType = http.mimeType?.lowercased()
        }
        responseReceived = true
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        cond.lock()
        defer { cond.unlock() }
        guard isCurrent(dataTask) else { return }
        buffer.append(data)
        bytesReceivedTotal += Int64(data.count)
        lastDataAt = Date()
        // Attempts count per incident: a connection that ran stable for a while ends it. A server
        // that accepts and drops again right away keeps counting towards giving up.
        if reconnectAttempts > 0 && lastDataAt.timeIntervalSince(connectedAt) > 10 { reconnectAttempts = 0 }
        if buffer.count - readIndex > highWater && !suspended {
            suspended = true
            dataTask.suspend()
        }
        cond.broadcast()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        cond.lock()
        defer { cond.broadcast(); cond.unlock() }
        guard isCurrent(task) else { return }
        if streaming && !cancelled && failure == nil {
            // Live streams do not end: a closed or failed connection is replaced.
            liveReconnect(reason: error.map { $0.localizedDescription } ?? String(localized: "Server hat Verbindung geschlossen"))
            return
        }
        if let error {
            if failure == nil && !cancelled { failure = error }
        } else {
            finished = true
        }
        self.task = nil
    }
}
