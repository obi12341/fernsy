import Foundation

/// Where Apple TV's guide window stands as time passes. It was set once when the guide was built,
/// so a guide left open overnight (tvOS keeps the app) still showed last night's hours, where only
/// archive channels have listings.
public enum GuideWindow {
    /// After the guide was out of sight this long, it opens at now again.
    public static let returnAfter: TimeInterval = 30 * 60

    /// Half an hour before the current half hour.
    public static func start(at now: Date = Date()) -> Date {
        let half = (now.timeIntervalSince1970 / 1800).rounded(.down) * 1800
        return Date(timeIntervalSince1970: half - 1800)
    }

    /// The new start for a window of `span` at `current`, or nil to keep it. A window the guide
    /// placed itself (`current == placed`) moves on to now once now is within half an hour of its
    /// end; one the user paged stays, unless the guide was out of sight for `returnAfter`.
    public static func update(current: Date, placed: Date, span: TimeInterval, hiddenFor: TimeInterval = 0, now: Date = Date()) -> Date? {
        let start = start(at: now)
        guard start != current else { return nil }
        if hiddenFor >= returnAfter { return start }
        guard current == placed, now >= current.addingTimeInterval(span - 1800) else { return nil }
        return start
    }
}
