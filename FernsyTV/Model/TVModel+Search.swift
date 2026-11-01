import FernsyCore
import FernsyPlayer
import Foundation

/// A page the library screens open: a film or series of either source.
enum DetailTarget: Hashable {
    case movie(Movie)
    case series(Series)
    case jellyfin(JFItem)

    static func of(_ target: LibraryEntry.Target) -> DetailTarget? {
        switch target {
        case .movie(let movie): .movie(movie)
        case .series(let series), .episode(_, let series): .series(series)
        case .jellyfin(let item): item.type == "Episode" ? nil : .jellyfin(item)
        case .recording: nil
        }
    }
}

/// A film or series found by Suche.
struct VODHit: Identifiable {
    let id: String
    let title: String
    let source: String
    let image: URL?
    let target: DetailTarget
}

/// What Suche and Jellyfin's Übersicht compute on Apple TV and iOS alike
/// (code-structure-cleanup 3.6).
extension TVModel {
    /// The channels searched: favourites, recently watched, then the first visible ones (at
    /// most 50, like the Mac's programme search).
    var searchChannels: [LiveChannel] {
        var seen = Set<Int>()
        return (channels(for: .favorites) + channels(for: .recent) + channels(for: .all))
            .filter { seen.insert($0.id).inserted }.prefix(50).map { $0 }
    }

    /// Shows on now or later whose title contains `query`, running ones first.
    func liveSearchHits(_ query: String) -> [(show: EPGEntry, channel: LiveChannel)] {
        let needle = makeSearchKey(query)
        guard needle.count >= 2 else { return [] }
        let now = Date()
        var hits: [(show: EPGEntry, channel: LiveChannel)] = []
        for channel in searchChannels {
            for show in guide.guide(channel.id).entries ?? [] where show.end > now && makeSearchKey(show.title).contains(needle) {
                hits.append((show, channel))
            }
        }
        return Array(hits.sorted { ($0.show.start <= now ? 0 : 1, $0.show.start) < ($1.show.start <= now ? 0 : 1, $1.show.start) }.prefix(12))
    }

    /// The search index over IPTV and Jellyfin films and series, built off the main thread.
    func searchIndex() async -> SearchIndex {
        let movies = movies.map(\.name), series = series.map(\.name)
        let films = jellyfin.films.map(\.name), shows = jellyfin.series.map(\.name)
        return await Task.detached(priority: .utility) {
            var entries: [SearchEntry] = []
            for (i, name) in movies.enumerated() { entries.append(SearchEntry(source: .movies, index: i, key: makeSearchKey(name))) }
            for (i, name) in series.enumerated() { entries.append(SearchEntry(source: .series, index: i, key: makeSearchKey(name))) }
            for (i, name) in films.enumerated() { entries.append(SearchEntry(source: .jellyfinFilms, index: i, key: makeSearchKey(name))) }
            for (i, name) in shows.enumerated() { entries.append(SearchEntry(source: .jellyfinSeries, index: i, key: makeSearchKey(name))) }
            return SearchIndex(entries: entries)
        }.value
    }

    /// Films and series matching `query` in `index`, at most 30.
    func vodSearchHits(_ query: String, in index: SearchIndex) -> [VODHit] {
        let found = index.search(makeSearchKey(query))
        var hits: [VODHit] = []
        for i in found[.movies] ?? [] where i < movies.count {
            let movie = movies[i]
            hits.append(VODHit(id: "m\(movie.id)", title: movie.name, source: "IPTV", image: movie.poster.flatMap(URL.init(string:)), target: .movie(movie)))
        }
        for i in found[.series] ?? [] where i < series.count {
            let show = series[i]
            hits.append(VODHit(id: "s\(show.id)", title: show.name, source: "IPTV", image: show.cover.flatMap(URL.init(string:)), target: .series(show)))
        }
        for i in (found[.jellyfinFilms] ?? []) where i < jellyfin.films.count {
            let item = jellyfin.films[i]
            hits.append(VODHit(id: "j\(item.id)", title: item.name, source: "Jellyfin", image: jellyfin.posterURL(item).flatMap(URL.init(string:)), target: .jellyfin(item)))
        }
        for i in (found[.jellyfinSeries] ?? []) where i < jellyfin.series.count {
            let item = jellyfin.series[i]
            hits.append(VODHit(id: "j\(item.id)", title: item.name, source: "Jellyfin", image: jellyfin.posterURL(item).flatMap(URL.init(string:)), target: .jellyfin(item)))
        }
        return Array(hits.prefix(30))
    }

    /// What Übersicht's rows read: the lists and the watched and favourite marks.
    var jellyfinOverviewInputs: String {
        let store = jellyfin
        let all = store.films + store.series
        let played = all.filter(\.isPlayed).count, favorites = all.filter(\.isFavorite).count
        let left = store.series.reduce(0) { $0 + ($1.userData?.unplayedItemCount ?? 0) }
        return "\(store.films.count).\(store.series.count).\(played).\(favorites).\(left)"
    }
}

/// Short texts the Apple TV and iOS screens share.
enum LibraryText {
    /// "Das Erste · on now, 12 min left" or "Das Erste · Mon 20:15", for a search hit.
    static func liveHit(_ show: EPGEntry, on channel: LiveChannel) -> String {
        if show.start <= Date() {
            let minutes = max(1, Int((show.end.timeIntervalSinceNow / 60).rounded()))
            return String(localized: "\(channel.displayName) · on now, \(minutes) min left")
        }
        return "\(channel.displayName) · \(show.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }

    /// "12 min left" of a running show.
    static func minutesLeft(_ show: EPGEntry) -> String {
        let minutes = max(1, Int((show.end.timeIntervalSinceNow / 60).rounded(.up)))
        return String(localized: "\(minutes) min left")
    }

    /// "20:15–21:45".
    static func span(_ show: EPGEntry) -> String {
        let style = Date.FormatStyle.dateTime.hour().minute()
        return "\(show.start.formatted(style))–\(show.end.formatted(style))"
    }

    /// The source tag of a Start entry.
    static func sourceName(_ source: LibraryEntry.Source) -> String {
        switch source {
        case .iptv: "IPTV"
        case .jellyfin: "Jellyfin"
        case .recording: String(localized: "Recording")
        }
    }

    /// "MOVIE", "SERIES" or "RECORDING" over Start's large entry.
    static func kind(_ target: LibraryEntry.Target) -> String {
        switch target {
        case .movie: String(localized: "MOVIE")
        case .series, .episode: String(localized: "SERIES")
        case .jellyfin(let item): item.type == "Episode" ? String(localized: "SERIES") : String(localized: "MOVIE")
        case .recording: String(localized: "RECORDING")
        }
    }
}
