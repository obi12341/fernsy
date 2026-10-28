import Foundation

/// The stretches of a guide window without listings (tvos-guide-empty-channels): Apple TV's
/// guide makes them focusable bars that play the channel, so every row can be reached.
public enum GuideGaps {
    /// Gaps shorter than this stay empty: a sliver would be hard to see and to hit.
    public static let minimum: TimeInterval = 15 * 60

    /// The free stretches of `window` between `shows` (sorted or not), each at least `minimum`
    /// long; the whole window when no show touches it.
    public static func free(shows: [EPGEntry], window: ClosedRange<Date>, minimum: TimeInterval = minimum) -> [ClosedRange<Date>] {
        var gaps: [ClosedRange<Date>] = []
        var cursor = window.lowerBound
        for show in shows.sorted(by: { $0.start < $1.start }) where show.end > window.lowerBound && show.start < window.upperBound {
            if show.start > cursor { gaps.append(cursor...min(show.start, window.upperBound)) }
            cursor = max(cursor, show.end)
            if cursor >= window.upperBound { break }
        }
        if cursor < window.upperBound { gaps.append(cursor...window.upperBound) }
        return gaps.filter { $0.upperBound.timeIntervalSince($0.lowerBound) >= minimum }
    }
}
