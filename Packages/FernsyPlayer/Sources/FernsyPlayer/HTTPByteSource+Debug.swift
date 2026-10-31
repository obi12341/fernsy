import FernsyCore
import Foundation

/// Debug test hooks of the download (IPTV_TESTNET and the trickle, forbid and close tests).
extension HTTPByteSource {
    #if DEBUG
    /// Test hooks: kill the connection outright, or silently stop receiving (a stalled socket).
    public func debugDropConnection() {
        cond.lock(); defer { cond.unlock() }
        task?.cancel()
    }

    public func debugStallConnection() {
        cond.lock(); defer { cond.unlock() }
        task?.suspend()
    }

    public func debugForbidNextEdge() {
        cond.lock(); defer { cond.unlock() }
        debugForbidEdge = true
    }

    public func debugFlakyEdge() {
        cond.lock(); defer { cond.unlock() }
        debugFlaky = true
        task?.cancel()
    }

    /// IPTV_TESTCLOCK=1 logs the content clock every 2 s.
    static let debugClock = ProcessInfo.processInfo.environment["IPTV_TESTCLOCK"] == "1"
    public func debugTrickle(kbit: Double) {
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


    /// Ends the throttling; what is still queued belongs to the old connection. Holds `cond`.
    func debugTrickleEnd() {
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

    public func debugCloseConnection() {
        cond.lock(); defer { cond.unlock() }
        debugCleanClose = true
        // A held (suspended) task only completes once it runs again.
        if suspended { task?.resume(); suspended = false }
        task?.cancel()
        debugLog("[test] download closed at \(bufferBase + Int64(buffer.count)) of \(contentLength) bytes")
    }
    #endif
}
