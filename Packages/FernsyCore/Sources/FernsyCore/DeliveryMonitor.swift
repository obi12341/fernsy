import Foundation

/// The slow-delivery rule of a live connection (playback spec, "Slow live delivery"; design B,
/// C and I of slow-live-stream-reconnect): how much content time arrived against wall time,
/// sampled by the connection's watchdog. A value type that takes the time as a parameter, so
/// tests can run minutes of delivery in microseconds. The connection keeps its lock, timers,
/// reconnects and log lines; this only measures and decides.
public struct DeliveryMonitor: Sendable {
    /// What the rule decides for a connection.
    public enum Decision: Equatable, Sendable {
        case keep
        /// Data keeps arriving, but too little: `delivered` s of content in the last `window` s.
        case replace(delivered: Double, window: TimeInterval)
        /// Slow again within 2 minutes after a switch for slowness: switching did not help, so
        /// this connection is judged over the longer `window` first.
        case lengthen(delivered: Double, window: TimeInterval)
    }

    /// One sample's view of the connection.
    public struct Reading: Equatable, Sendable {
        /// Content delivered over the current window; nil until the connection has a full one.
        public let delivered: Double?
        /// Slower than real time right now (for the player's card; never replaces by itself).
        public let slow: Bool

        public static let none = Reading(delivered: nil, slow: false)
    }

    private var samples: [(wall: Date, content: Double)] = []
    private var lastSlowAt = Date.distantPast
    private var lastSwitchAt = Date.distantPast
    /// Doublings of the window after switches that did not help (0: 15 s, 1: 30 s, 2: 60 s).
    public private(set) var level = 0
    /// Per connection, for the log line that tunes the rule against real providers.
    public private(set) var lowestWindow: Double?
    public private(set) var longestPause: TimeInterval = 0

    /// A channel sending 6 s segments in bursts, on average in real time, still delivers 9 s in
    /// 15 s (60 %); the window doubles with `level`.
    public var window: TimeInterval { 15 * Double(1 << level) }
    var minimum: Double { 0.6 * window }
    /// The server's replay and first bytes, plus a full window.
    var minimumAge: TimeInterval { window + 5 }

    public init() {}

    public var sampleCount: Int { samples.count }

    /// A connection was answered: samples and per-connection figures start over.
    public mutating func connectionAnswered() {
        samples = []
        lowestWindow = nil
        longestPause = 0
    }

    /// The pause before a chunk of data arrived.
    public mutating func notePause(_ seconds: TimeInterval) {
        longestPause = max(longestPause, seconds)
    }

    /// Takes a sample of the content clock (nil before the first content).
    public mutating func sample(at now: Date, content: Double?) -> Reading {
        if let content {
            samples.append((now, content))
            samples.removeAll { now.timeIntervalSince($0.wall) > 61 }
        }
        guard let latest = samples.last, let first = samples.first else { return .none }
        if let past = samples.last(where: { now.timeIntervalSince($0.wall) >= 15 }) {
            let content = latest.content - past.content
            lowestWindow = min(lowestWindow ?? content, content)
        }
        var delivered: Double?
        var slow = false
        if let past = samples.last(where: { now.timeIntervalSince($0.wall) >= window }) {
            let content = latest.content - past.content
            delivered = content
            slow = content < minimum
            if slow { lastSlowAt = now }
        } else if latest.wall.timeIntervalSince(first.wall) >= 10 {
            // A young connection: well under real time since it was answered.
            slow = latest.content - first.content < 0.6 * latest.wall.timeIntervalSince(first.wall)
        }
        // For the player's card only: the player may run dry before the full window shows it.
        // 6 s bursts still bring 6 s in any 12 s.
        if !slow, let recent = samples.last(where: { now.timeIntervalSince($0.wall) >= 12 }),
           latest.content - recent.content < 5 {
            slow = true
        }
        return Reading(delivered: delivered, slow: slow)
    }

    /// Whether a connection of this age gets replaced, judged on this sample's reading.
    public mutating func decide(at now: Date, reading: Reading, connectionAge: TimeInterval) -> Decision {
        guard let delivered = reading.delivered, delivered < minimum, connectionAge >= minimumAge else { return .keep }
        defer { lastSwitchAt = now }
        if now.timeIntervalSince(lastSwitchAt) < 120 && level < 2 {
            level += 1
            return .lengthen(delivered: delivered, window: window)
        }
        return .replace(delivered: delivered, window: window)
    }

    /// Back to the 15 s window after 5 minutes without slow delivery; true when it went back.
    public mutating func relax(at now: Date) -> Bool {
        guard level > 0, now.timeIntervalSince(lastSlowAt) > 300, now.timeIntervalSince(lastSwitchAt) > 300 else { return false }
        level = 0
        return true
    }

    /// The connection had a full window below the threshold within `seconds`.
    public func wasSlow(within seconds: TimeInterval, at now: Date) -> Bool {
        now.timeIntervalSince(lastSlowAt) < seconds
    }

    /// Since it was answered, the connection has delivered at least 5 s, in real time.
    public var deliversInRealTime: Bool {
        guard let latest = samples.last, let first = samples.first else { return false }
        let elapsed = latest.wall.timeIntervalSince(first.wall)
        return elapsed >= 5 && latest.content - first.content >= 0.9 * elapsed
    }
}
