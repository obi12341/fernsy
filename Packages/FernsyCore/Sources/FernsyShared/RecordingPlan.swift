import Foundation

/// How planned recordings share the account's streams: recordings on one channel share a
/// connection, so what counts at any moment is the number of distinct channels.
///
/// - `blockers` refuses a show whose own time (without padding) does not fit.
/// - `windows` widens the show times by their padding as far as the limit allows: first every
///   after-padding (by show end), then every before-padding (by show start). Padding therefore
///   never reaches into another show, and an earlier show's after-padding wins over a later
///   show's before-padding.
public enum RecordingPlan: Sendable {
    public struct Item: Sendable {
        public let id: UUID
        public let channelId: Int
        public let start: Date
        public let end: Date
        public let padBefore: TimeInterval
        public let padAfter: TimeInterval
        /// Running recordings keep the start they actually had.
        public var runningSince: Date?

        public init(id: UUID, channelId: Int, start: Date, end: Date, padBefore: TimeInterval, padAfter: TimeInterval, runningSince: Date? = nil) {
            self.id = id
            self.channelId = channelId
            self.start = start
            self.end = end
            self.padBefore = padBefore
            self.padAfter = padAfter
            self.runningSince = runningSince
        }
    }

    public struct Window: Equatable, Sendable {
        public var start: Date
        public var end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
    }

    private struct Span {
        let id: UUID
        let channelId: Int
        var start: Date
        var end: Date
    }

    /// The recordings in the way when `item`'s show is added to `others`' shows, or an empty
    /// list when it fits. Only the time from `now` on counts.
    public static func blockers(for item: Item, among others: [Item], limit: Int, now: Date) -> [UUID] {
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
    public static func windows(for items: [Item], limit: Int, now: Date) -> [UUID: Window] {
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
}
