import Foundation

/// Content the provider did not deliver during a recording (10 s or more), as stored in the
/// recordings list.
public struct RecordingGap: Codable, Equatable, Sendable {
    /// When the missing content would have been on air.
    public let at: Date
    public let seconds: TimeInterval

    public init(at: Date, seconds: TimeInterval) {
        self.at = at
        self.seconds = seconds
    }
}

/// Missing content in a running recording. Wall time minus content time (the deficit) stays
/// steady while the provider delivers in real time and grows while it delivers too little;
/// the writer's timeline never carries the hole as a jump (see design H of
/// slow-live-stream-reconnect).
public struct GapTracker: Sendable {
    private var origin: (wall: Date, content: Double)?
    /// Deficit before the current growth, and the last time it was there.
    private var baseline = 0.0
    private var lastAtBaseline = Date()
    /// Deficit that has held (within 1 s) since `referenceAt`.
    private var reference = 0.0
    private var referenceAt = Date()
    private var last: (wall: Date, deficit: Double)?
    /// Raw deficits of the last 6 s: channels that deliver in bursts make the deficit a saw
    /// tooth; its lower edge is the content really missing.
    private var recent: [(wall: Date, deficit: Double)] = []
    private let minimum: TimeInterval = 10

    public init() {}

    /// A gap of 10 s or more that this sample closes (the deficit held still for 5 s).
    public mutating func sample(wall: Date, content: Double) -> RecordingGap? {
        guard let origin else {
            origin = (wall, content)
            lastAtBaseline = wall
            referenceAt = wall
            return nil
        }
        let raw = wall.timeIntervalSince(origin.wall) - (content - origin.content)
        recent.append((wall, raw))
        recent.removeAll { wall.timeIntervalSince($0.wall) > 6 }
        let deficit = recent.map(\.deficit).min() ?? raw
        last = (wall, deficit)
        if deficit <= baseline + 1 {
            baseline = min(baseline, deficit)
        }
        // Where a growth began: the raw deficit leaves the baseline at once, the smoothed one
        // only up to 6 s later.
        if raw <= baseline + 1 {
            lastAtBaseline = wall
        }
        if abs(deficit - reference) > 1 {
            reference = deficit
            referenceAt = wall
        }
        guard wall.timeIntervalSince(referenceAt) >= 5, deficit > baseline + 1 else { return nil }
        return close(at: wall, deficit: deficit)
    }

    /// The recording ends: a gap still growing counts as well.
    public mutating func finish() -> RecordingGap? {
        guard let last, last.deficit > baseline + 1 else { return nil }
        return close(at: last.wall, deficit: last.deficit)
    }

    private mutating func close(at wall: Date, deficit: Double) -> RecordingGap? {
        let growth = deficit - baseline
        let start = lastAtBaseline
        baseline = deficit
        lastAtBaseline = wall
        // Short hiccups are absorbed into the baseline.
        return growth >= minimum ? RecordingGap(at: start, seconds: growth) : nil
    }
}
