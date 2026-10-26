import Foundation
import Testing
@testable import FernsyCore

/// Gaps in recordings (recordings spec, design H of slow-live-stream-reconnect): wall time
/// against the content the recording received, sampled once a second.
struct GapTrackerTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Runs `seconds` samples; `content(t)` is the content time received by second t.
    static func run(_ seconds: Int, content: (Int) -> Double) -> (gaps: [RecordingGap], atEnd: RecordingGap?) {
        var tracker = GapTracker()
        var gaps: [RecordingGap] = []
        for t in 0...seconds {
            if let gap = tracker.sample(wall: start.addingTimeInterval(Double(t)), content: content(t)) { gaps.append(gap) }
        }
        return (gaps, tracker.finish())
    }

    @Test func steadyDeliveryHasNoGap() {
        let result = Self.run(300) { Double($0) }
        #expect(result.gaps.isEmpty)
        #expect(result.atEnd == nil)
    }

    @Test func burstsAreNoGap() {
        // A channel that delivers 3 s at a time: the deficit is a saw tooth between 0 and 3 s.
        let result = Self.run(300) { Double($0 / 3 * 3) }
        #expect(result.gaps.isEmpty)
        #expect(result.atEnd == nil)
    }

    @Test func holeIsListedWhileTheRecordingRuns() throws {
        // Nothing from second 30 to 55, then real time again (25 s missing).
        let result = Self.run(120) { t in t < 30 ? Double(t) : t < 55 ? 30 : Double(t - 25) }
        let gap = try #require(result.gaps.first)
        #expect(result.gaps.count == 1)
        #expect(abs(gap.seconds - 25) < 2)
        #expect(abs(gap.at.timeIntervalSince(Self.start) - 30) < 3)
        #expect(result.atEnd == nil)
    }

    @Test func holeInBurstyDeliveryIsOneGap() throws {
        let result = Self.run(150) { t in
            let delivered = t < 40 ? t : t < 62 ? 40 : t - 22
            return Double(delivered / 3 * 3)
        }
        let gap = try #require(result.gaps.first)
        #expect(result.gaps.count == 1)
        #expect(abs(gap.seconds - 22) < 4)
    }

    @Test func shortHiccupIsNoGap() {
        // 8 s missing: under the 10 s a gap needs.
        let result = Self.run(120) { t in t < 30 ? Double(t) : t < 38 ? 30 : Double(t - 8) }
        #expect(result.gaps.isEmpty)
        #expect(result.atEnd == nil)
    }

    @Test func gapStillGrowingWhenTheRecordingEnds() throws {
        let result = Self.run(70) { t in t < 50 ? Double(t) : 50 }
        #expect(result.gaps.isEmpty)
        let gap = try #require(result.atEnd)
        #expect(gap.seconds >= 14)
    }

    @Test func gapsKeepTheirFileFormat() throws {
        let gap = RecordingGap(at: Self.start, seconds: 25)
        let json = try JSONEncoder().encode(gap)
        let keys = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any]).keys.sorted()
        #expect(keys == ["at", "seconds"])
        #expect(try JSONDecoder().decode(RecordingGap.self, from: json) == gap)
    }
}
