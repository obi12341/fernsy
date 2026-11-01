import AVFoundation
import CFFShim
import CoreMedia
import CoreVideo
import FernsyCore

/// Debug fault injection (IPTV_TESTNODATA, IPTV_TESTNET).
extension PlaybackSession {
    #if DEBUG
    /// IPTV_TESTNODATA=<offline|silent>:<s>: for that many seconds after the first tuner
    /// connection, tuner connections fail as an offline channel, or (silent) deliver nothing and
    /// time out after 8 s – a recording has to keep waiting for its channel.
    private static let noDataTest: (offline: Bool, until: Date)? = {
        let parts = ProcessInfo.processInfo.environment["IPTV_TESTNODATA"]?.split(separator: ":") ?? []
        guard parts.count == 2, let seconds = Double(parts[1]) else { return nil }
        return (parts[0] == "offline", Date().addingTimeInterval(seconds))
    }()

    func simulateNoData() throws {
        guard isTuner, let test = Self.noDataTest, Date() < test.until else { return }
        debugLog("[test] simulating a channel without data (\(test.offline ? "offline" : "silent"))")
        if test.offline { throw PlayerError.offline }
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline && !isStopped { Thread.sleep(forTimeInterval: 0.1) }
        throw HTTPByteSource.SourceError.timeout
    }

    /// IPTV_TESTNET="drop:15,stall:40,close:60": kill the connection / stall the socket / end the
    /// download as if the server had closed it cleanly, at those seconds after start – the live
    /// reconnect and, for films, continuing an interrupted download. "forbid:<s>": the next
    /// reconnect to the edge gets a 403; "flaky:<s>": drops now and 6 s after the reconnect;
    /// "trickle:<s>": the connection delivers only IPTV_TRICKLEKBIT kbit/s (default 300) until the
    /// next reconnect.
    func scheduleNetworkTest() {
        guard let spec = ProcessInfo.processInfo.environment["IPTV_TESTNET"] else { return }
        for item in spec.split(separator: ",") {
            let parts = item.split(separator: ":")
            guard parts.count == 2, let at = Double(parts[1]) else { continue }
            let kind = String(parts[0])
            DispatchQueue.global().asyncAfter(deadline: .now() + at) { [weak self] in
                guard let self, !self.isStopped else { return }
                debugLog("[test] simulating network \(kind)")
                guard let http = self.source as? HTTPByteSource else { return }
                switch kind {
                case "drop": http.debugDropConnection()
                case "close": http.debugCloseConnection()
                case "forbid": http.debugForbidNextEdge()
                case "flaky": http.debugFlakyEdge()
                case "trickle":
                    let kbit = ProcessInfo.processInfo.environment["IPTV_TRICKLEKBIT"].flatMap(Double.init) ?? 300
                    http.debugTrickle(kbit: kbit)
                default: http.debugStallConnection()
                }
            }
        }
    }
    #endif
}
