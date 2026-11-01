import Foundation

/// Texts and numbers for library items that the Mac, Apple TV and iOS apps share
/// (code-structure-cleanup 3.3).
public enum ItemText {
    /// "Mon 3 Nov, 20:15": weekday, day, month and time, for archive shows and recordings.
    public static func shortDateTime(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    /// "Das Erste · Mon 3 Nov, 20:15".
    public static func channelAndTime(_ channel: String, _ date: Date) -> String {
        "\(channel) · \(shortDateTime(date))"
    }
}

/// Jellyfin counts time in ticks of 100 ns.
public enum JellyfinTicks {
    public static func seconds(_ ticks: Int64) -> Double { Double(ticks) / 10_000_000 }
    public static func ticks(_ seconds: Double) -> Int64 { Int64(seconds * 10_000_000) }
}

public extension JFItem {
    /// The runtime in seconds, when the server knows it.
    var runTimeSeconds: Double? { runTimeTicks.map(JellyfinTicks.seconds) }
    /// Where the user stopped, in seconds (0 when not started).
    var positionSeconds: Double { JellyfinTicks.seconds(userData?.playbackPositionTicks ?? 0) }
}

public extension SeriesInfo {
    /// Episodes of loaded series by id, so Continue Watching can name them.
    static func episodeIndex(_ infos: [Int: SeriesInfo], series: (Int) -> Series?) -> [String: (Episode, Series)] {
        var index: [String: (Episode, Series)] = [:]
        for (id, info) in infos {
            guard let show = series(id) else { continue }
            for episode in info.seasons.values.flatMap({ $0 }) { index[episode.id] = (episode, show) }
        }
        return index
    }
}
