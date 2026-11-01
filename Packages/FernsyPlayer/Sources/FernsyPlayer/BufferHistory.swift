import Combine
import FernsyCore
import Foundation

/// Buffer level over time for the info overlay. Separate object so the once-per-second
/// samples only re-render the chart.
public final class BufferHistory: ObservableObject {
    public enum Event { case reconnect, restart, rebuffer }

    public struct Sample: Identifiable {
        public let id: Int
        public let time: Date
        /// Demuxed and waiting in the player.
        public let player: Double
        /// Received but not yet demuxed, converted at the average data rate.
        public let network: Double
        public let events: [Event]
    }

    public static let window: TimeInterval = 120

    @Published public private(set) var samples: [Sample] = []
    /// Average over the last 30 s; single seconds are useless for bursty channels.
    @Published public private(set) var averageMbps = 0.0

    private var nextID = 0
    private var rates: [Double] = []
    private var previous: PlaybackStats?

    public func reset() {
        samples = []
        rates = []
        averageMbps = 0
        previous = nil
    }

    /// The restart count is passed separately: it lives in the engine, not in the session.
    /// `disk`: timeshift, seconds stored ahead of the player (instead of network bytes).
    public func record(_ stats: PlaybackStats, disk: Double? = nil) {
        rates.append(stats.bitrateMbps)
        if rates.count > 30 { rates.removeFirst(rates.count - 30) }
        averageMbps = rates.reduce(0, +) / Double(rates.count)

        var events: [Event] = []
        if let previous {
            // Session counters restart from zero after a full restart.
            if stats.restarts > previous.restarts { events.append(.restart) }
            else if stats.seamlessReconnects > previous.seamlessReconnects { events.append(.reconnect) }
            if stats.rebuffers > previous.rebuffers { events.append(.rebuffer) }
        }
        previous = stats

        let rate = averageMbps * 125_000
        let network = disk ?? (rate > 0 ? Double(stats.networkBufferBytes) / rate : 0)
        let now = Date()
        samples.append(Sample(id: nextID, time: now, player: stats.bufferSeconds, network: network, events: events))
        nextID += 1
        if let first = samples.firstIndex(where: { now.timeIntervalSince($0.time) <= Self.window }), first > 0 {
            samples.removeFirst(first)
        }
    }
}
