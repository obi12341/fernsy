import Foundation

/// How planned recordings share the account's streams: recordings on one channel share a
/// connection, so what counts at any moment is the number of distinct channels.
///
/// - `blockers` refuses a show whose own time (without padding) does not fit.
/// - `windows` widens the show times by their padding as far as the limit allows: first every
///   after-padding (by show end), then every before-padding (by show start). Padding therefore
///   never reaches into another show, and an earlier show's after-padding wins over a later
///   show's before-padding.
enum RecordingPlan {
    struct Item {
        let id: UUID
        let channelId: Int
        let start: Date
        let end: Date
        let padBefore: TimeInterval
        let padAfter: TimeInterval
        /// Running recordings keep the start they actually had.
        var runningSince: Date?
    }

    struct Window: Equatable {
        var start: Date
        var end: Date
    }

    private struct Span {
        let id: UUID
        let channelId: Int
        var start: Date
        var end: Date
    }

    /// The recordings in the way when `item`'s show is added to `others`' shows, or an empty
    /// list when it fits. Only the time from `now` on counts.
    static func blockers(for item: Item, among others: [Item], limit: Int, now: Date) -> [UUID] {
        let new = Span(id: item.id, channelId: item.channelId, start: max(item.start, now), end: item.end)
        guard new.end > new.start else { return [] }
        let spans = others.filter { $0.id != item.id }.map {
            Span(id: $0.id, channelId: $0.channelId, start: max($0.runningSince ?? $0.start, now), end: $0.end)
        }.filter { $0.end > $0.start }
        // The channel count only rises where a span starts.
        let moments = [new.start] + spans.map(\.start).filter { $0 > new.start && $0 < new.end }
        var inTheWay: [UUID] = []
        for moment in moments {
            let active = spans.filter { $0.start <= moment && moment < $0.end }
            let channels = Set(active.map(\.channelId)).union([new.channelId])
            guard channels.count > limit else { continue }
            for span in active where span.channelId != new.channelId && !inTheWay.contains(span.id) {
                inTheWay.append(span.id)
            }
        }
        return inTheWay
    }

    /// Each item's recording window within the limit.
    static func windows(for items: [Item], limit: Int, now: Date) -> [UUID: Window] {
        var spans = items.map { Span(id: $0.id, channelId: $0.channelId, start: $0.runningSince ?? $0.start, end: $0.end) }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        // 1. After-padding, earliest show end first.
        for index in spans.indices.sorted(by: { spans[$0].end < spans[$1].end }) {
            guard let item = byID[spans[index].id], item.padAfter > 0 else { continue }
            let from = spans[index].end, to = from.addingTimeInterval(item.padAfter)
            var end = to
            for (a, _) in pieces(from: from, to: to, spans: spans, except: index) where blocked(at: a, spans, except: index, limit: limit) {
                end = a
                break
            }
            if item.runningSince != nil { end = max(end, min(to, now)) }
            spans[index].end = end
        }
        // 2. Before-padding, earliest show start first; running recordings keep their start.
        for index in spans.indices.sorted(by: { spans[$0].start < spans[$1].start }) {
            guard let item = byID[spans[index].id], item.runningSince == nil, item.padBefore > 0 else { continue }
            let to = spans[index].start, from = to.addingTimeInterval(-item.padBefore)
            var start = from
            for (a, b) in pieces(from: from, to: to, spans: spans, except: index).reversed() where blocked(at: a, spans, except: index, limit: limit) {
                start = b
                break
            }
            spans[index].start = start
        }
        return Dictionary(uniqueKeysWithValues: spans.map { ($0.id, Window(start: $0.start, end: $0.end)) })
    }

    /// `from…to` cut where another span starts or ends, so the channel count is constant within
    /// each piece.
    private static func pieces(from: Date, to: Date, spans: [Span], except index: Int) -> [(Date, Date)] {
        var cuts = Set([from, to])
        for (i, span) in spans.enumerated() where i != index {
            for t in [span.start, span.end] where t > from && t < to { cuts.insert(t) }
        }
        let sorted = cuts.sorted()
        return zip(sorted, sorted.dropFirst()).map { ($0, $1) }
    }

    /// Whether the span at `index` would need one stream too many at `moment`.
    private static func blocked(at moment: Date, _ spans: [Span], except index: Int, limit: Int) -> Bool {
        let channels = Set(spans.enumerated().filter { $0.offset != index && $0.element.start <= moment && moment < $0.element.end }.map(\.element.channelId))
        return !channels.contains(spans[index].channelId) && channels.count + 1 > limit
    }

    #if DEBUG
    /// IPTV_PLANTEST=1: the spec's examples.
    static func selfTest() {
        let day = Date(timeIntervalSince1970: 1_893_456_000) // 2030-01-01 00:00 UTC
        func at(_ h: Int, _ m: Int) -> Date { day.addingTimeInterval(Double(h * 3600 + m * 60)) }
        let format = DateFormatter()
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "HH:mm"
        let pad: TimeInterval = 600
        func show(_ channel: Int, _ from: Date, _ to: Date, running: Date? = nil) -> Item {
            Item(id: UUID(), channelId: channel, start: from, end: to, padBefore: pad, padAfter: pad, runningSince: running)
        }
        func check(_ name: String, _ items: [Item], limit: Int, now: Date = day, expect: [String]) {
            let windows = windows(for: items, limit: limit, now: now)
            let got = items.map { item in windows[item.id].map { "\(format.string(from: $0.start))-\(format.string(from: $0.end))" } ?? "-" }
            debugLog("[test] recording plan \(got == expect ? "pass" : "FAIL"): \(name) → \(got.joined(separator: ", "))\(got == expect ? "" : " (expected \(expect.joined(separator: ", ")))")")
        }
        func checkRefusal(_ name: String, _ new: Item, _ others: [Item], limit: Int, expect: Int) {
            let count = blockers(for: new, among: others, limit: limit, now: day).count
            debugLog("[test] recording plan \(count == expect ? "pass" : "FAIL"): \(name) → \(count) in the way\(count == expect ? "" : " (expected \(expect))")")
        }

        let a = show(1, at(20, 15), at(21, 45))
        let b = show(2, at(21, 45), at(23, 0))
        check("back to back, 1 stream", [a, b], limit: 1, expect: ["20:05-21:45", "21:45-23:10"])
        check("6-minute gap, 1 stream", [a, show(2, at(21, 51), at(23, 0))], limit: 1, expect: ["20:05-21:51", "21:51-23:10"])
        check("same channel, 1 stream", [a, show(1, at(21, 45), at(23, 0))], limit: 1, expect: ["20:05-21:55", "21:35-23:10"])
        check("full padding, 2 streams", [a, b], limit: 2, expect: ["20:05-21:55", "21:35-23:10"])
        check("neighbour removed", [a], limit: 1, expect: ["20:05-21:55"])
        check("three channels, 2 streams", [a, b, show(3, at(21, 50), at(23, 0))], limit: 2,
              expect: ["20:05-21:50", "21:35-23:10", "21:50-23:10"])
        check("running recording, 1 stream", [show(1, at(20, 15), at(21, 45), running: at(20, 5)), b], limit: 1, now: at(21, 0),
              expect: ["20:05-21:45", "21:45-23:10"])
        check("running, into its after-padding", [show(1, at(20, 15), at(21, 45), running: at(20, 5)), show(2, at(21, 52), at(23, 0))],
              limit: 1, now: at(21, 50), expect: ["20:05-21:52", "21:52-23:10"])
        check("limit lowered to 1", [a, b], limit: 1, expect: ["20:05-21:45", "21:45-23:10"])

        let tatort = show(1, at(20, 15), at(21, 45))
        let other = show(2, at(21, 0), at(22, 0))
        checkRefusal("real overlap, 1 stream", other, [tatort], limit: 1, expect: 1)
        checkRefusal("real overlap, 2 streams", other, [tatort], limit: 2, expect: 0)
        checkRefusal("real overlap, same channel", show(1, at(21, 0), at(22, 0)), [tatort], limit: 1, expect: 0)
        let third = show(3, at(21, 10), at(21, 40))
        checkRefusal("three shows at once, 2 streams", third, [tatort, other], limit: 2, expect: 2)
        checkRefusal("three shows at once, 3 streams", third, [tatort, other], limit: 3, expect: 0)
        checkRefusal("back to back is no overlap", b, [a], limit: 1, expect: 0)
    }
    #endif
}
