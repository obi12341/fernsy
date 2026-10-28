import Foundation

/// The provider's archive of a channel (catch-up): which past shows can be played from it.
/// Only the channel's own archive counts, never a sibling's with the same programme (user
/// decision 2026-10-28).
public enum Archive {
    /// The guide never reaches further back than this, whatever a provider claims.
    public static let maxDays = 7

    /// A show that has started (running or over), on a channel with an archive, that began
    /// within the archive's days.
    public static func isPlayable(_ show: EPGEntry, on channel: LiveChannel, now: Date = Date()) -> Bool {
        guard channel.archiveDays > 0, show.start <= now else { return false }
        let days = min(channel.archiveDays, maxDays)
        return show.start >= now.addingTimeInterval(-Double(days) * 86_400)
    }

    /// Minutes to request for a show: its length and 5 minutes for a late end.
    public static func minutes(for show: EPGEntry) -> Int {
        Int((show.end.timeIntervalSince(show.start) / 60).rounded(.up)) + 5
    }

    /// The days the guide reaches back for these channels: their longest archive (at most
    /// `maxDays`), 0 without archive channels.
    public static func reach(of channels: [LiveChannel]) -> Int {
        min(channels.map(\.archiveDays).max() ?? 0, maxDays)
    }
}
