import Foundation

/// Follows the playing position against an episode's marks (jellyfin-media-segments, design 4
/// and 7): which skip button shows, whether the final credits play, and when automatic skipping
/// jumps. Pure, so the rules are tested without a player.
public struct SegmentTracker: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case enteredCredits
        /// Seeked back before the credits.
        case leftCredits
        /// Automatic skipping: seek to `to`.
        case autoSkip(kind: SegmentMarks.SkipKind, to: Double)
    }

    public private(set) var marks: SegmentMarks = .none
    public var skipping: SegmentPreferences.Skipping
    public private(set) var activeSkip: SegmentMarks.Skip?
    public private(set) var inCredits = false
    /// Ranges skipped automatically already (by start): seeking back into one plays it.
    private var autoSkipped: Set<Double> = []
    private var position: Double = 0

    public init(skipping: SegmentPreferences.Skipping = .button) {
        self.skipping = skipping
    }

    /// The marks arrived (possibly after playback started): evaluated at once.
    public mutating func setMarks(_ marks: SegmentMarks) -> [Event] {
        self.marks = marks
        return update(position: position)
    }

    public mutating func update(position: Double) -> [Event] {
        self.position = position
        var events: [Event] = []
        let skip = marks.skip(at: position)
        switch skipping {
        case .never:
            activeSkip = nil
        case .button:
            activeSkip = skip
        case .auto:
            activeSkip = nil
            if let skip, !autoSkipped.contains(skip.start) {
                autoSkipped.insert(skip.start)
                events.append(.autoSkip(kind: skip.kind, to: skip.end))
            }
        }
        let credits = marks.isInCredits(position)
        if credits != inCredits {
            inCredits = credits
            events.append(credits ? .enteredCredits : .leftCredits)
        }
        return events
    }
}

/// What the next-episode card shows (design 4 and 6).
public struct NextCardState: Equatable, Sendable {
    public enum Reason: Equatable, Sendable { case credits, end }
    public var reason: Reason
    /// The countdown runs.
    public var counts: Bool
    /// "Are you still watching?" instead of a countdown.
    public var asksStillWatching: Bool

    public init(reason: Reason, counts: Bool, asksStillWatching: Bool) {
        self.reason = reason
        self.counts = counts
        self.asksStillWatching = asksStillWatching
    }

    /// nil: no card. `ended`: the file played to its end; `dismissed`: Watch Credits, Cancel or
    /// Back on this item.
    public static func decide(hasNext: Bool, ended: Bool, inCredits: Bool, creditsReachEnd: Bool, dismissed: Bool,
                              autoplay: Bool, stillWatchingDue: Bool) -> NextCardState? {
        guard hasNext, !dismissed, ended || inCredits else { return nil }
        let reason: Reason = ended ? .end : .credits
        let wouldCount = autoplay && (ended || creditsReachEnd)
        return NextCardState(reason: reason, counts: wouldCount && !stillWatchingDue, asksStillWatching: wouldCount && stillWatchingDue)
    }
}

/// Episodes the countdown started in a row without input from the user (design 6).
public struct AutoplayStreak: Equatable, Sendable {
    public var count = 0
    public var limit: Int

    public init(limit: Int = 3) {
        self.limit = limit
    }

    public var isDue: Bool { count >= limit }
    public mutating func autoStarted() { count += 1 }
    public mutating func userInput() { count = 0 }
}
