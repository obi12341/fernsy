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
        case connectionLost

        var errorDescription: String? {
            switch self {
            case .http(let code): return String(localized: "Server antwortet mit HTTP \(code)")
            case .timeout: return String(localized: "Zeitüberschreitung beim Verbinden")
            case .cancelled: return String(localized: "Abgebrochen")
            case .connectionLost: return String(localized: "Verbindung zum Server verloren")
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
    /// Attempts to continue a film's interrupted download; reset once data flows again.
    private var continueAttempts = 0
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
    /// The player has (almost) run dry: waiting the full stall timeout only lengthens a freeze
    /// the user already sees. Only while a player reports its buffer (not for recording-only
    /// tuners, whose figure is stale).
    private let dryStallTimeout: TimeInterval = 2
    private let dryPlaybackAhead: Double = 1
    private var playbackAhead: Double = 0
    private var playbackAheadAt = Date.distantPast
    /// The current reconnect attempt goes to the edge host (not the load balancer).
    private var attemptToEdge = false
    /// This incident skips the edge: it rejected us (403/401), or it stalled again right after
    /// the last reconnect to it.
    private var avoidEdge = false
    /// Host and time of the last successful reconnect, to notice an edge that fails again.
    private var lastReconnectHost: String?
    private var lastReconnectAt = Date.distantPast
    private var requestStartedAt = Date()
    private var net = NetStats()
    private let maxReconnectAttempts = 8

    /// Live: the newest content time received, on the tuner's continuous timeline. Read by the
    /// watchdog outside `cond` (the buffer's stats provider takes `cond` under its own lock).
    var contentClock: (() -> Double?)?
    /// Live: the connection's health changed (watchdog queue).
    var onHealth: ((Health) -> Void)?
    /// Live: a reconnect via the load balancer ended slow or silent delivery, and the new
    /// connection runs in real time (watchdog queue).
    var onRecovered: (() -> Void)?

    enum Health: Equatable {
        case ok
        /// Less content than real time arrives.
        case slow
        /// No data for as long as the stall rule waits (bursts with shorter pauses are fine).
        case silent
        case reconnecting(loadBalancer: Bool)
    }

    // Slow delivery: content time against wall time over a window, sampled by the watchdog
    // and cleared when a connection is answered.
    private var contentSamples: [(wall: Date, content: Double)] = []
    private var lastSlowAt = Date.distantPast
    private var health = Health.ok
    /// The current incident began while the connection was slow or silent.
    private var incidentUnhealthy = false
    /// After such an incident the new connection still has to prove itself: until it delivered
    /// 5 s in real time (at most 20 s), the health stays at the reconnect.
    private var proving: (loadBalancer: Bool, since: Date)?
    /// A load-balancer reconnect after slow or silent delivery waits for real-time content.
    private var recoveryPending = false
    /// A channel sending 6 s segments in bursts, on average in real time, still delivers 9 s in
    /// 15 s (60 %). When the connection after a switch is slow again, switching did not help
    /// (longer bursts at this provider, or a slow line of the user's own): each such repeat
    /// doubles the window, up to 60 s, instead of switching servers every 20 s.
    private var slowLevel = 0
    private var slowWindow: TimeInterval { 15 * Double(1 << slowLevel) }
    private var slowMinimum: Double { 0.6 * slowWindow }
    /// The server's replay and first bytes, plus a full window.
    private var slowMinAge: TimeInterval { slowWindow + 5 }
    private var lastSlowSwitchAt = Date.distantPast
    // Per connection, for the log (tuning the rule against real providers).
    private var lowestWindow: Double?
    private var longestPause: TimeInterval = 0

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
        if streaming && !reconnecting && !cancelled { logConnectionSummary() }
        cancelled = true
        task?.cancel()
        task = nil
        watchdog?.cancel()
        watchdog = nil
        #if DEBUG
        debugTrickleTimer?.cancel()
        debugTrickleTimer = nil
        #endif
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

    /// The next reconnect to the edge is answered as if with HTTP 403 (expired edge token).
    private var debugForbidEdge = false
    func debugForbidNextEdge() {
        cond.lock(); defer { cond.unlock() }
        debugForbidEdge = true
    }

    /// Drops now and again 6 s after the next successful reconnect (an edge that fails again).
    private var debugFlaky = false
    func debugFlakyEdge() {
        cond.lock(); defer { cond.unlock() }
        debugFlaky = true
        task?.cancel()
    }

    /// The current connection delivers at this rate (kbit/s) until the next reconnect: received
    /// bytes wait in a queue and are handed on in small portions every 0.1 s, and the task is held
    /// while the queue is full, so the server sees a slow reader too.
    private var debugTrickleKbit: Double = 0
    private var debugTrickleQueue = Data()
    private var debugTrickleHeld = false
    private var debugTrickleTimer: DispatchSourceTimer?
    /// IPTV_TESTCLOCK=1 logs the content clock every 2 s.
    private static let debugClock = ProcessInfo.processInfo.environment["IPTV_TESTCLOCK"] == "1"
    func debugTrickle(kbit: Double) {
        cond.lock(); defer { cond.unlock() }
        debugTrickleKbit = kbit
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in self?.debugTrickleTick() }
        debugTrickleTimer?.cancel()
        debugTrickleTimer = timer
        timer.resume()
    }

    private func debugTrickleTick() {
        cond.lock(); defer { cond.unlock() }
        guard debugTrickleKbit > 0, !debugTrickleQueue.isEmpty else { return }
        let n = min(debugTrickleQueue.count, Int(debugTrickleKbit * 1000 / 8 / 10))
        buffer.append(debugTrickleQueue.prefix(n))
        debugTrickleQueue.removeFirst(n)
        bytesReceivedTotal += Int64(n)
        lastDataAt = Date()
        if debugTrickleHeld && debugTrickleQueue.count < 64 << 10 {
            debugTrickleHeld = false
            if !suspended { task?.resume() }
        }
        cond.broadcast()
    }

    /// IPTV_TRICKLEMORE=<n|all>: that many later connections trickle too ("all": a slow line of
    /// the user's own).
    private var debugTrickleMore: Int = {
        guard let value = ProcessInfo.processInfo.environment["IPTV_TRICKLEMORE"] else { return 0 }
        return Int(value) ?? .max
    }()

    /// Ends the throttling; what is still queued belongs to the old connection. Holds `cond`.
    private func debugTrickleEnd() {
        guard debugTrickleKbit > 0 else { return }
        buffer.append(debugTrickleQueue)
        debugTrickleQueue = Data()
        debugTrickleHeld = false
        if debugTrickleMore > 0 {
            debugTrickleMore -= 1
            return
        }
        debugTrickleKbit = 0
        debugTrickleTimer?.cancel()
        debugTrickleTimer = nil
    }

    /// The server ends the response early without an error (an idle connection closed by a proxy).
    private var debugCleanClose = false
    func debugCloseConnection() {
        cond.lock(); defer { cond.unlock() }
        debugCleanClose = true
        // A held (suspended) task only completes once it runs again.
        if suspended { task?.resume(); suspended = false }
        task?.cancel()
        debugLog("[test] download closed at \(bufferBase + Int64(buffer.count)) of \(contentLength) bytes")
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
        playbackAheadAt = Date()
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
        contentSamples = []
        lowestWindow = nil
        longestPause = 0
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
        let content = contentClock?()
        cond.lock()
        guard streaming, !cancelled, failure == nil else { cond.unlock(); return }
        let now = Date()
        if let content, !reconnecting {
            contentSamples.append((now, content))
            contentSamples.removeAll { now.timeIntervalSince($0.wall) > 61 }
        }
        // Content delivered over the full window (nil until the connection has one), and
        // whether delivery is slower than real time right now.
        var delivered: Double?
        var slow = false
        if !reconnecting, let latest = contentSamples.last, let first = contentSamples.first {
            if let past = contentSamples.last(where: { now.timeIntervalSince($0.wall) >= 15 }) {
                let content = latest.content - past.content
                lowestWindow = min(lowestWindow ?? content, content)
            }
            if let past = contentSamples.last(where: { now.timeIntervalSince($0.wall) >= slowWindow }) {
                let content = latest.content - past.content
                delivered = content
                slow = content < slowMinimum
                if slow { lastSlowAt = now }
            } else if latest.wall.timeIntervalSince(first.wall) >= 10 {
                // A young connection: well under real time since it was answered.
                slow = latest.content - first.content < 0.6 * latest.wall.timeIntervalSince(first.wall)
            }
            // For the player's card only: the player may run dry before the full window shows it.
            // 6 s bursts still bring 6 s in any 12 s.
            if !slow, let recent = contentSamples.last(where: { now.timeIntervalSince($0.wall) >= 12 }),
               latest.content - recent.content < 5 {
                slow = true
            }
        }
        let idle = now.timeIntervalSince(lastDataAt)
        #if DEBUG
        if Self.debugClock, Int(now.timeIntervalSince1970 * 2) % 4 == 0 {
            debugLog("[clock] content \(content.map { String(format: "%.1f", $0) } ?? "nil"), in window \(delivered.map { String(format: "%.1f", $0) } ?? "-"), samples \(contentSamples.count), idle \(String(format: "%.1f", idle))")
        }
        #endif
        if reconnecting {
            // A reconnect whose response does not arrive is retried like a failed one.
            if task != nil && now.timeIntervalSince(reconnectStartedAt) > 6 {
                liveReconnect(reason: String(localized: "keine Antwort"))
            }
        } else if !suspended {
            let playerReports = now.timeIntervalSince(playbackAheadAt) < 2
            if idle > hardStallTimeout || (idle > stallTimeout && playbackAhead < lowPlaybackAhead) {
                liveReconnect(reason: String(format: String(localized: "keine Daten seit %.0f s, %.1f s Vorrat"), idle, playbackAhead))
            } else if playerReports && idle > dryStallTimeout && playbackAhead < dryPlaybackAhead
                        && now.timeIntervalSince(connectedAt) > stallTimeout {
                // A fresh connection gets the normal time for its first bytes (servers often
                // fetch their buffer first), or reconnects would chain.
                liveReconnect(reason: String(format: String(localized: "keine Daten seit %.0f s, Player fast leer (%.1f s Vorrat)"), idle, playbackAhead))
            } else if let delivered, delivered < slowMinimum, now.timeIntervalSince(connectedAt) >= slowMinAge {
                if now.timeIntervalSince(lastSlowSwitchAt) < 120 && slowLevel < 2 {
                    // Slow again right after a switch: give this connection a longer window first.
                    slowLevel += 1
                    lastSlowSwitchAt = now
                    AppLog.info(.network, "slow again after switching servers (\(String(format: "%.0f", delivered)) s of content), judging over \(Int(slowWindow)) s instead of switching again")
                } else {
                    // Data keeps arriving, but too little to keep up: replaced like a stall.
                    lastSlowSwitchAt = now
                    liveReconnect(reason: String(format: String(localized: "zu langsam: %.0f s Inhalt in %.0f s"), delivered, slowWindow), slow: true)
                }
            }
        }
        if slowLevel > 0 && now.timeIntervalSince(lastSlowAt) > 300 && now.timeIntervalSince(lastSlowSwitchAt) > 300 {
            slowLevel = 0
            AppLog.info(.network, "no slow delivery for 5 minutes, judging over 15 s again")
        }

        // A load-balancer reconnect that ended slow or silent delivery: 5 s of content in real time.
        var recovered = false
        if (recoveryPending || proving != nil) && !reconnecting, let latest = contentSamples.last, let first = contentSamples.first {
            let elapsed = latest.wall.timeIntervalSince(first.wall)
            if elapsed >= 5 && latest.content - first.content >= 0.9 * elapsed {
                proving = nil
                if recoveryPending {
                    recoveryPending = false
                    recovered = true
                    AppLog.info(.network, "another server delivers in real time again")
                }
            }
        }
        if let started = proving?.since, now.timeIntervalSince(started) > 20 { proving = nil }
        let newHealth: Health = reconnecting ? .reconnecting(loadBalancer: !attemptToEdge)
            : idle >= stallTimeout ? .silent
            : proving.map { .reconnecting(loadBalancer: $0.loadBalancer) } ?? (slow ? .slow : .ok)
        let changed = newHealth != health
        if changed {
            AppLog.detail(.network, "connection health: \(health) → \(newHealth)")
            health = newHealth
        }
        let onHealth = onHealth, onRecovered = onRecovered
        cond.unlock()
        if changed { onHealth?(newHealth) }
        if recovered { onRecovered?() }
    }

    /// One line per live connection that ran long enough for a window: how it delivered, to tune
    /// the slow rule against real providers. The caller holds `cond`.
    private func logConnectionSummary() {
        let lasted = Date().timeIntervalSince(connectedAt)
        guard streaming, lasted >= 20 else { return }
        let window = lowestWindow.map { String(format: "%.1f s", $0) } ?? "-"
        AppLog.info(.network, "connection ran \(Int(lasted) / 60):\(String(format: "%02d", Int(lasted) % 60)), lowest 15 s window \(window) of content, longest pause between data \(String(format: "%.1f", longestPause)) s")
    }

    /// Replaces the current connection; the caller holds `cond`. `immediate`: no backoff (the
    /// edge rejected us, the load balancer is a different server). `slow`: the connection
    /// delivered too little, so its edge is skipped.
    private func liveReconnect(reason: String, immediate: Bool = false, slow: Bool = false) {
        task?.cancel()
        task = nil
        taskGeneration += 1
        suspended = false
        #if DEBUG
        debugTrickleEnd()
        #endif
        guard reconnectAttempts < maxReconnectAttempts else {
            AppLog.error(.network, "giving up after \(reconnectAttempts) reconnects (\(reason))")
            failure = SourceError.timeout
            cond.broadcast()
            return
        }
        reconnectAttempts += 1
        if !reconnecting {
            logConnectionSummary()
            reconnecting = true
            incidentAttempts = 0
            // An edge that stalls again right after we reconnected to it is skipped this time, and
            // so is one that delivered too slowly (it is the problem itself, see design C of
            // slow-live-stream-reconnect).
            let failsAgain = Date().timeIntervalSince(lastReconnectAt) < 20 && lastReconnectHost != nil
                && lastReconnectHost == edgeURL?.host
            let wasSlow = slow || Date().timeIntervalSince(lastSlowAt) < 60
            avoidEdge = failsAgain || wasSlow
            incidentUnhealthy = wasSlow || health == .slow || health == .silent || recoveryPending
            recoveryPending = false
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
        AppLog.warning(.network, "live reconnect #\(reconnectAttempts): \(reason), \(String(format: "%.1f", Double(buffer.count - readIndex) / 1e6)) MB still buffered")
        let generation = taskGeneration
        // First try the same edge; if its token or slot is gone, go through the load balancer.
        attemptToEdge = incidentAttempts == 1 && !avoidEdge && edgeURL != nil
        let target = attemptToEdge ? (edgeURL ?? url) : url
        // The first retry is quick; later ones give single-connection servers time to
        // release the old slot.
        let delay = immediate || (incidentAttempts == 1 && slow) ? 0 : reconnectAttempts == 1 ? 0.2 : 0.5 * Double(reconnectAttempts)
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
            var status = http?.statusCode ?? 200
            #if DEBUG
            if debugForbidEdge && attemptToEdge {
                debugForbidEdge = false
                status = 403
                debugLog("[test] edge answers 403")
            }
            #endif
            let target = http?.url?.absoluteString.lowercased() ?? ""
            if target.contains("stream_offline") || target.contains("offline.mp4") {
                // The channel went offline: hand over to a full restart, which reports it.
                failure = SourceError.http(status)
                completionHandler(.cancel)
            } else if (200..<300).contains(status) {
                reconnecting = false
                if let edge = http?.url { edgeURL = edge }
                lastReconnectHost = http?.url?.host
                lastReconnectAt = Date()
                #if DEBUG
                if debugFlaky {
                    debugFlaky = false
                    let generation = taskGeneration
                    watchdogQueue.asyncAfter(deadline: .now() + 6) { [weak self] in
                        guard let self else { return }
                        self.cond.lock(); defer { self.cond.unlock() }
                        guard self.taskGeneration == generation else { return }
                        debugLog("[test] flaky edge drops again")
                        self.task?.cancel()
                    }
                }
                #endif
                net.connectTime = Date().timeIntervalSince(requestStartedAt)
                connectedAt = Date()
                lastDataAt = Date()
                contentSamples = []
                lowestWindow = nil
                longestPause = 0
                recoveryPending = incidentUnhealthy && !attemptToEdge
                proving = incidentUnhealthy ? (!attemptToEdge, Date()) : nil
                AppLog.info(.network, "reconnected (HTTP \(status)) via \(http?.url?.host ?? "?")\(attemptToEdge ? " (same edge)" : " (load balancer)")")
                completionHandler(.allow)
            } else {
                completionHandler(.cancel)
                // The edge's token expired: the load balancer is another server, no need to
                // wait for a slot.
                let rejectedByEdge = attemptToEdge && (status == 403 || status == 401)
                if rejectedByEdge { avoidEdge = true }
                liveReconnect(reason: "HTTP \(status)", immediate: rejectedByEdge)
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
            // Seeks and continued downloads ask for exactly this byte.
            let expected = bufferBase + Int64(buffer.count)
            if let range = http.value(forHTTPHeaderField: "Content-Range"),
               let start = range.split(separator: " ").last?.split(separator: "-").first.flatMap({ Int64($0) }),
               start != expected {
                failure = SourceError.http(http.statusCode)
                completionHandler(.cancel)
                return
            }
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
        if isLive {
            // The host only: the path carries the account's credentials.
            AppLog.info(.network, "connected (HTTP \(http.statusCode)) via \(http.url?.host ?? "?")")
        }
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
        #if DEBUG
        if debugTrickleKbit > 0 {
            debugTrickleQueue.append(data)
            if debugTrickleQueue.count > 256 << 10 && !debugTrickleHeld {
                debugTrickleHeld = true
                dataTask.suspend()
            }
            return
        }
        #endif
        buffer.append(data)
        bytesReceivedTotal += Int64(data.count)
        continueAttempts = 0
        if streaming && !reconnecting { longestPause = max(longestPause, Date().timeIntervalSince(lastDataAt)) }
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
        var error = error
        #if DEBUG
        if debugCleanClose {
            debugCleanClose = false
            error = nil
        }
        #endif
        if streaming && !cancelled && failure == nil {
            // Live streams do not end: a closed or failed connection is replaced.
            liveReconnect(reason: error.map { $0.localizedDescription } ?? String(localized: "Server hat Verbindung geschlossen"))
            return
        }
        // A film's download that ends before the file does was interrupted (an idle connection
        // closed during a long pause, or dropped) – not the end of the film.
        let received = bufferBase + Int64(buffer.count)
        if !cancelled && failure == nil && contentLength > 0 && received < contentLength {
            self.task = nil
            continueDownload(at: received, reason: error?.localizedDescription ?? "closed by the server")
            return
        }
        if let error {
            if failure == nil && !cancelled { failure = error }
        } else {
            finished = true
        }
        self.task = nil
    }

    /// Requests the rest of the file from `offset`, keeping what is buffered (`connect(at:)`
    /// starts over). Called with `cond` locked.
    private func continueDownload(at offset: Int64, reason: String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["IPTV_TESTNOCONTINUE"] == "1" {
            finished = true  // the old behaviour, to test the plausibility check of the end
            return
        }
        #endif
        guard supportsRanges, continueAttempts < 5 else {
            failure = SourceError.connectionLost
            return
        }
        let delay = [0.5, 1, 2, 4, 4][continueAttempts]
        continueAttempts += 1
        AppLog.warning(.network, "download interrupted at \(offset) of \(contentLength) (\(reason)), continuing (attempt \(continueAttempts))")
        taskGeneration += 1
        responseReceived = false
        suspended = false
        var request = URLRequest(url: url)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        let newTask = session.dataTask(with: request)
        newTask.taskDescription = String(taskGeneration)
        task = newTask
        requestStartedAt = Date()
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { newTask.resume() }
    }
}
