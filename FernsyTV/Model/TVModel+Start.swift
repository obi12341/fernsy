import FernsyCore
import FernsyPlayer
import Foundation

/// Start's rows beyond Continue Watching and Recently Added (tvos-start-rows): live channels,
/// tonight's shows, the largest categories and genres, recordings and best rated films.
struct StartRows {
    struct Row: Identifiable {
        let id: String
        let title: String
        let entries: [LibraryEntry]
    }

    /// The large entry when nothing is to continue: the newest film.
    var spotlight: LibraryEntry?
    var categories: [Row] = []
    var bestRated: [LibraryEntry] = []
    // Kept with the catalog rows (tvos-start-scrolling): StartScreen rebuilds each part when
    // what it shows changes, never while scrolling.
    var added: [LibraryEntry] = []
    var resume: [LibraryEntry] = []
    var nextUp: [LibraryEntry] = []
    var recordings: [LibraryEntry] = []
    var live: (source: LiveSource, channels: [LiveChannel]) = (.all, [])
    var tonight: (title: String, shows: [(show: EPGEntry, channel: LiveChannel)]) = ("", [])
}

extension TVModel {
    /// Rows from the catalog, built once per catalog change (StartScreen keeps them and adds the
    /// other parts): grouping 30,000 films on every redraw would stall the screen.
    func startRows() -> StartRows {
        var rows = StartRows()
        rows.added = recentlyAdded
        rows.spotlight = rows.added.first { entry in
            switch entry.open {
            case .movie: true
            case .jellyfin(let item): item.type == "Movie"
            default: false
            }
        }
        // The provider's largest film and series categories, newest first in each.
        let filmGroups = Dictionary(grouping: movies, by: { $0.categoryId ?? "" })
        for category in movieCategories.sorted(by: { (filmGroups[$0.id]?.count ?? 0) > (filmGroups[$1.id]?.count ?? 0) }).prefix(3) {
            let films = (filmGroups[category.id] ?? []).sorted { $0.added > $1.added }.prefix(15)
            guard films.count >= 3 else { continue }
            rows.categories.append(StartRows.Row(id: "films." + category.id, title: String(localized: "Movies · \(category.displayName)"),
                                                 entries: films.map(Self.entry)))
        }
        let seriesGroups = Dictionary(grouping: series, by: { $0.categoryId ?? "" })
        for category in seriesCategories.sorted(by: { (seriesGroups[$0.id]?.count ?? 0) > (seriesGroups[$1.id]?.count ?? 0) }).prefix(2) {
            let shows = (seriesGroups[category.id] ?? []).sorted { $0.lastModified > $1.lastModified }.prefix(15)
            guard shows.count >= 3 else { continue }
            rows.categories.append(StartRows.Row(id: "series." + category.id, title: String(localized: "Series · \(category.displayName)"),
                                                 entries: shows.map(Self.entry)))
        }
        // Jellyfin: the two most common film genres.
        var genreCounts: [String: Int] = [:]
        for film in jellyfin.films { for genre in film.genres ?? [] { genreCounts[genre, default: 0] += 1 } }
        for genre in genreCounts.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(2).map(\.key) {
            let films = jellyfin.films.filter { $0.genres?.contains(genre) == true }.prefix(15)
            guard films.count >= 3 else { continue }
            rows.categories.append(StartRows.Row(id: "jf.genre." + genre, title: "Jellyfin · \(genre)", entries: films.map(jellyfinEntry)))
        }
        rows.bestRated = movies.filter { ($0.rating ?? 0) >= 7 && $0.poster?.isEmpty == false }
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }.prefix(15).map(Self.entry)
        return rows
    }

    /// The channels of "Jetzt live" and "Heute Abend": favourites, else recently watched, else
    /// the first channels, so a new account has the row too.
    var startChannels: (source: LiveSource, channels: [LiveChannel]) {
        for source in [LiveSource.favorites, .recent] {
            let list = channels(for: source)
            if !list.isEmpty { return (source, Array(list.prefix(12))) }
        }
        return (.all, Array(channels(for: .all).prefix(12)))
    }

    /// Tonight's prime time (20:00–21:30) on `channels`, one show each, by start; after 21:30
    /// what starts in the next two hours.
    func tonight(on channels: [LiveChannel], now: Date = Date()) -> (title: String, shows: [(show: EPGEntry, channel: LiveChannel)]) {
        let calendar = Calendar.current
        let from = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
        let to = calendar.date(bySettingHour: 21, minute: 30, second: 0, of: now) ?? now
        let primeTime = now < to
        let window = primeTime ? from...to : now...now.addingTimeInterval(2 * 3600)
        var shows: [(show: EPGEntry, channel: LiveChannel)] = []
        for channel in channels {
            if let show = (guide.guide(channel.id).entries ?? []).first(where: { window.contains($0.start) && $0.end > now }) {
                shows.append((show, channel))
            }
        }
        return (primeTime ? String(localized: "Tonight") : String(localized: "Coming Up"), shows.sorted { $0.show.start < $1.show.start })
    }

    /// Jellyfin's next episodes.
    var nextUpEntries: [LibraryEntry] {
        jellyfin.nextUp.prefix(15).map { item in
            LibraryEntry(id: "jf.next." + item.id, title: item.seriesName ?? item.name, detail: VODItem.jellyfin(item).subtitle ?? item.name,
                         source: .jellyfin, image: (jellyfin.backdropURL(item) ?? jellyfin.posterURL(item)).flatMap(URL.init(string:)),
                         progress: nil, date: .distantPast, open: .jellyfin(item))
        }
    }

    /// The newest finished recordings.
    var recordingEntries: [LibraryEntry] {
        recorder.recordings.filter { $0.status == .done }.sorted { $0.start > $1.start }.prefix(12).map { recording in
            LibraryEntry(id: "rec." + recording.id.uuidString, title: recording.title,
                         detail: "\(recording.channelName) · \(recording.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))",
                         source: .recording, image: channels.first { $0.id == recording.channelId }?.icon.flatMap(URL.init(string:)),
                         progress: resume.fraction(ResumeStore.recordingKey(recording.id)), date: recording.start, open: .recording(recording))
        }
    }

    private static func entry(_ movie: Movie) -> LibraryEntry {
        LibraryEntry(id: "movie:\(movie.id)", title: movie.name, detail: "IPTV", source: .iptv, image: movie.poster.flatMap(URL.init(string:)),
                     progress: nil, date: Date(timeIntervalSince1970: Double(movie.added)), open: .movie(movie))
    }

    private static func entry(_ show: Series) -> LibraryEntry {
        LibraryEntry(id: "series:\(show.id)", title: show.name, detail: "IPTV", source: .iptv, image: show.cover.flatMap(URL.init(string:)),
                     progress: nil, date: Date(timeIntervalSince1970: Double(show.lastModified)), open: .series(show))
    }

    private func jellyfinEntry(_ item: JFItem) -> LibraryEntry {
        LibraryEntry(id: "jf." + item.id, title: item.name, detail: "Jellyfin", source: .jellyfin,
                     image: jellyfin.posterURL(item).flatMap(URL.init(string:)), progress: nil, date: .distantPast, open: .jellyfin(item))
    }
}
