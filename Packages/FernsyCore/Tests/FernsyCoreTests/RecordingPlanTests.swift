import Foundation
import Testing
@testable import FernsyCore

/// The recordings spec's examples for sharing the account's streams.
struct RecordingPlanTests {
    static let day = Date(timeIntervalSince1970: 1_893_456_000) // 2030-01-01 00:00 UTC
    static func at(_ h: Int, _ m: Int) -> Date { day.addingTimeInterval(Double(h * 3600 + m * 60)) }
    static let pad: TimeInterval = 600

    static func show(_ channel: Int, _ from: Date, _ to: Date, running: Date? = nil) -> RecordingPlan.Item {
        RecordingPlan.Item(id: UUID(), channelId: channel, start: from, end: to, padBefore: pad, padAfter: pad, runningSince: running)
    }

    static func times(_ items: [RecordingPlan.Item], limit: Int, now: Date = day) -> [String] {
        let format = DateFormatter()
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "HH:mm"
        let windows = RecordingPlan.windows(for: items, limit: limit, now: now)
        return items.map { item in windows[item.id].map { "\(format.string(from: $0.start))-\(format.string(from: $0.end))" } ?? "-" }
    }

    static let a = show(1, at(20, 15), at(21, 45))
    static let b = show(2, at(21, 45), at(23, 0))

    struct WindowCase: CustomTestStringConvertible, Sendable {
        let name: String
        let items: [RecordingPlan.Item]
        let limit: Int
        var now = RecordingPlanTests.day
        let expected: [String]
        var testDescription: String { name }
    }

    static let windowCases: [WindowCase] = [
        WindowCase(name: "back to back, 1 stream", items: [a, b], limit: 1, expected: ["20:05-21:45", "21:45-23:10"]),
        WindowCase(name: "6-minute gap, 1 stream", items: [a, show(2, at(21, 51), at(23, 0))], limit: 1, expected: ["20:05-21:51", "21:51-23:10"]),
        WindowCase(name: "same channel, 1 stream", items: [a, show(1, at(21, 45), at(23, 0))], limit: 1, expected: ["20:05-21:55", "21:35-23:10"]),
        WindowCase(name: "full padding, 2 streams", items: [a, b], limit: 2, expected: ["20:05-21:55", "21:35-23:10"]),
        WindowCase(name: "neighbour removed", items: [a], limit: 1, expected: ["20:05-21:55"]),
        WindowCase(name: "three channels, 2 streams", items: [a, b, show(3, at(21, 50), at(23, 0))], limit: 2,
                   expected: ["20:05-21:50", "21:35-23:10", "21:50-23:10"]),
        WindowCase(name: "running recording, 1 stream", items: [show(1, at(20, 15), at(21, 45), running: at(20, 5)), b], limit: 1,
                   now: at(21, 0), expected: ["20:05-21:45", "21:45-23:10"]),
        WindowCase(name: "running, into its after-padding",
                   items: [show(1, at(20, 15), at(21, 45), running: at(20, 5)), show(2, at(21, 52), at(23, 0))], limit: 1,
                   now: at(21, 50), expected: ["20:05-21:52", "21:52-23:10"]),
        WindowCase(name: "limit lowered to 1", items: [a, b], limit: 1, expected: ["20:05-21:45", "21:45-23:10"]),
    ]

    @Test(arguments: windowCases)
    func windows(_ c: WindowCase) {
        #expect(Self.times(c.items, limit: c.limit, now: c.now) == c.expected)
    }

    static let tatort = show(1, at(20, 15), at(21, 45))
    static let other = show(2, at(21, 0), at(22, 0))
    static let third = show(3, at(21, 10), at(21, 40))

    struct RefusalCase: CustomTestStringConvertible, Sendable {
        let name: String
        let new: RecordingPlan.Item
        let others: [RecordingPlan.Item]
        let limit: Int
        let inTheWay: Int
        var testDescription: String { name }
    }

    static let refusalCases: [RefusalCase] = [
        RefusalCase(name: "real overlap, 1 stream", new: other, others: [tatort], limit: 1, inTheWay: 1),
        RefusalCase(name: "real overlap, 2 streams", new: other, others: [tatort], limit: 2, inTheWay: 0),
        RefusalCase(name: "real overlap, same channel", new: show(1, at(21, 0), at(22, 0)), others: [tatort], limit: 1, inTheWay: 0),
        RefusalCase(name: "three shows at once, 2 streams", new: third, others: [tatort, other], limit: 2, inTheWay: 2),
        RefusalCase(name: "three shows at once, 3 streams", new: third, others: [tatort, other], limit: 3, inTheWay: 0),
        RefusalCase(name: "back to back is no overlap", new: b, others: [a], limit: 1, inTheWay: 0),
    ]

    @Test(arguments: refusalCases)
    func blockers(_ c: RefusalCase) {
        #expect(RecordingPlan.blockers(for: c.new, among: c.others, limit: c.limit, now: Self.day).count == c.inTheWay)
    }
}
