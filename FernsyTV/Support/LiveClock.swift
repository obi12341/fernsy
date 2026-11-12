import Foundation
import SwiftUI

/// "Now" for the live parts of Start on Apple TV, iPhone and iPad (start-live-clock), as the
/// Mac's `LiveClock`. In debug builds `IPTV_CLOCKOFFSET=<s>` shifts it, so a show ends while
/// a test watches.
enum LiveClock {
    #if DEBUG
    private static let offset = ProcessInfo.processInfo.environment["IPTV_CLOCKOFFSET"].flatMap(Double.init) ?? 0
    #else
    private static let offset: Double = 0
    #endif

    static func now(_ date: Date = Date()) -> Date { date.addingTimeInterval(offset) }

    /// `now()` at its full minute: views drawn at different seconds of a minute show the same time.
    static func minute(_ date: Date = Date()) -> Date {
        Date(timeIntervalSince1970: (now(date).timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    /// Every full minute, counted in seconds rather than by the calendar: `.everyMinute`
    /// stalls in the hour that repeats when daylight saving time ends.
    static var everyMinute: PeriodicTimelineSchedule {
        let seconds = now().timeIntervalSince1970
        return .periodic(from: Date().addingTimeInterval((seconds / 60).rounded(.down) * 60 - seconds), by: 60)
    }

    /// Seconds until the next full minute of `now()`.
    static func secondsToNextMinute() -> Double {
        let seconds = now().timeIntervalSince1970
        return max(1, (seconds / 60).rounded(.down) * 60 + 60 - seconds)
    }
}
