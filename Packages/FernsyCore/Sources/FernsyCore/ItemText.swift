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

    /// "S1 E2", in German "S1 F2" (Staffel, Folge): every app names episodes this way
    /// (episode-label-next-episode).
    public static func episodeCode(season: Int, episode: Int) -> String {
        String(localized: "S\(season) E\(episode)", bundle: .module,
               comment: "Episode code: season and episode number (German: S1 F2)")
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
    /// "S1 E2" (German "S1 F2") when the server knows season and episode number.
    var episodeCode: String? {
        guard let season = parentIndexNumber, let episode = indexNumber else { return nil }
        return ItemText.episodeCode(season: season, episode: episode)
    }
    /// "S1 E2 · Title" for an episode, its name alone when the numbers are missing.
    var episodeLine: String { [episodeCode, name].compactMap { $0 }.joined(separator: " · ") }
}

public extension Episode {
    /// "S1 E2" (German "S1 F2").
    var code: String { ItemText.episodeCode(season: season, episode: number) }
}

public extension SeriesInfo {
    /// The episode to continue with, the same on every app (episode-label-next-episode): the one
    /// with a resume position, else the one after the last watched episode; the first when none
    /// is watched, the last when all are. Episodes go by season, then number.
    func nextEpisode(position: (Episode) -> Double, watched: (Episode) -> Bool) -> Episode? {
        let all = seasons.keys.sorted().flatMap { (seasons[$0] ?? []).sorted { $0.number < $1.number } }
        if let started = all.first(where: { position($0) > 0 }) { return started }
        guard let last = all.lastIndex(where: watched) else { return all.first }
        return last + 1 < all.count ? all[last + 1] : all[last]
    }

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
