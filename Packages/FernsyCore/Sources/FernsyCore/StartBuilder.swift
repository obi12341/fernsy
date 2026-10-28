import Foundation

/// One entry of Start's rows, from any source (tvos-start-rows; shared with the Mac by
/// mac-start-pages).
public struct LibraryEntry: Identifiable {
    public enum Source { case iptv, jellyfin, recording }

    /// What a click opens. Recordings by id: they live in FernsyPlayer, which FernsyCore cannot
    /// name; each app resolves the id.
    public enum Target {
        case movie(Movie), series(Series), episode(Episode, Series), jellyfin(JFItem), recording(UUID)
    }

    public let id: String
    public let title: String
    public let detail: String
    public let source: Source
    public let image: URL?
    /// 0…1 watched, nil when not started.
    public let progress: Double?
    public let date: Date
    public let open: Target

    public init(id: String, title: String, detail: String, source: Source, image: URL?, progress: Double?, date: Date, open: Target) {
        self.id = id
        self.title = title
        self.detail = detail
        self.source = source
        self.image = image
        self.progress = progress
        self.date = date
        self.open = open
    }
}

/// A recording as Start needs it (the app maps its `Recording`).
public struct StartRecording: Sendable {
    public let id: UUID
    public let title: String
    public let channelId: Int
    public let channelName: String
    public let start: Date
    public let recordStart: Date
    public let recordEnd: Date
    /// Finished (done), or ended with an error (failed): both can be watched.
    public let finished: Bool
    public let failed: Bool

    public init(id: UUID, title: String, channelId: Int, channelName: String, start: Date, recordStart: Date, recordEnd: Date,
                finished: Bool, failed: Bool) {
        self.id = id
        self.title = title
        self.channelId = channelId
        self.channelName = channelName
        self.start = start
        self.recordStart = recordStart
        self.recordEnd = recordEnd
        self.finished = finished
        self.failed = failed
    }
}

/// Start's rows. Both apps keep them in state and rebuild each part when its inputs change,
/// never while drawing (tvos-start-scrolling).
public struct StartRows {
    public struct Row: Identifiable {
        public let id: String
        public let title: String
        public let entries: [LibraryEntry]
    }

    /// The large entry when nothing is to continue: the newest film.
    public var spotlight: LibraryEntry?
    public var categories: [Row] = []
    public var bestRated: [LibraryEntry] = []
    public var added: [LibraryEntry] = []
    public var resume: [LibraryEntry] = []
    public var nextUp: [LibraryEntry] = []
    public var recordings: [LibraryEntry] = []
    public var live: (source: LiveSource, channels: [LiveChannel]) = (.all, [])
    public var tonight: (title: String, shows: [(show: EPGEntry, channel: LiveChannel)]) = ("", [])

    public init() {}
}

/// The rules of Start's rows, the same on Mac and Apple TV (mac-start-pages design 1). The apps
/// fill in their data; nothing here touches a store or the network.
public struct StartBuilder {
    /// Image URLs of Jellyfin items (from `JellyfinStore`).
    public struct JellyfinImages {
        public var poster: (JFItem) -> String?
        public var thumb: (JFItem) -> String?
        public var backdrop: (JFItem) -> String?

        public init(poster: @escaping (JFItem) -> String?, thumb: @escaping (JFItem) -> String?, backdrop: @escaping (JFItem) -> String?) {
            self.poster = poster
            self.thumb = thumb
            self.backdrop = backdrop
        }
    }

    public var movies: [Movie] = []
    public var series: [Series] = []
    public var movieCategories: [XCategory] = []
    public var seriesCategories: [XCategory] = []
    public var jellyfinFilms: [JFItem] = []
    public var jellyfinLatestFilms: [JFItem] = []
    public var jellyfinLatestSeries: [JFItem] = []
    public var jellyfinResume: [JFItem] = []
    public var jellyfinNextUp: [JFItem] = []
    public var images = JellyfinImages(poster: { _ in nil }, thumb: { _ in nil }, backdrop: { _ in nil })
    public var resume: ResumeStore?
    /// Episodes of loaded series by id, so Continue Watching can name them.
    public var episodeIndex: [String: (Episode, Series)] = [:]
    public var recordings: [StartRecording] = []
    /// For the recordings' channel logos.
    public var channels: [LiveChannel] = []

    public init() {}

    // MARK: Catalog rows

    /// Rows from the catalog: Recently Added, the spotlight, the largest categories and genres,
    /// Best Rated. Built once per catalog change: grouping 30,000 films is not for every redraw.
    public func catalogRows() -> StartRows {
        var rows = StartRows()
        rows.added = recentlyAdded()
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
            rows.categories.append(StartRows.Row(id: "films." + category.id,
                                                 title: String(localized: "Movies · \(category.displayName)", bundle: .module),
                                                 entries: films.map(Self.entry)))
        }
        let seriesGroups = Dictionary(grouping: series, by: { $0.categoryId ?? "" })
        for category in seriesCategories.sorted(by: { (seriesGroups[$0.id]?.count ?? 0) > (seriesGroups[$1.id]?.count ?? 0) }).prefix(2) {
            let shows = (seriesGroups[category.id] ?? []).sorted { $0.lastModified > $1.lastModified }.prefix(15)
            guard shows.count >= 3 else { continue }
            rows.categories.append(StartRows.Row(id: "series." + category.id,
                                                 title: String(localized: "Series · \(category.displayName)", bundle: .module),
                                                 entries: shows.map(Self.entry)))
        }
        // Jellyfin: the two most common film genres.
        var genreCounts: [String: Int] = [:]
        for film in jellyfinFilms { for genre in film.genres ?? [] { genreCounts[genre, default: 0] += 1 } }
        for genre in genreCounts.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(2).map(\.key) {
            let films = jellyfinFilms.filter { $0.genres?.contains(genre) == true }.prefix(15)
            guard films.count >= 3 else { continue }
            rows.categories.append(StartRows.Row(id: "jf.genre." + genre, title: "Jellyfin · \(genre)", entries: films.map(jellyfinEntry)))
        }
        rows.bestRated = movies.filter { ($0.rating ?? 0) >= 7 && $0.poster?.isEmpty == false }
            .sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }.prefix(15).map(Self.entry)
        return rows
    }

    /// The newest IPTV films and series and Jellyfin items, interleaved by date.
    public func recentlyAdded() -> [LibraryEntry] {
        var entries: [LibraryEntry] = []
        for movie in movies.sorted(by: { $0.added > $1.added }).prefix(12) { entries.append(Self.entry(movie)) }
        for show in series.sorted(by: { $0.lastModified > $1.lastModified }).prefix(8) { entries.append(Self.entry(show)) }
        for item in jellyfinLatestFilms + jellyfinLatestSeries {
            let date = item.dateCreated.flatMap { try? Date($0, strategy: .iso8601) } ?? .distantPast
            entries.append(LibraryEntry(id: "jf." + item.id, title: item.name, detail: "Jellyfin", source: .jellyfin,
                                        image: images.poster(item).flatMap(URL.init(string:)), progress: nil, date: date, open: .jellyfin(item)))
        }
        return Array(entries.sorted { $0.date > $1.date }.prefix(24))
    }

    // MARK: Personal rows

    /// Partly watched films and episodes of the IPTV account, Jellyfin items and recordings,
    /// newest first.
    public func continueWatching() -> [LibraryEntry] {
        var entries: [LibraryEntry] = []
        if let resume {
            let moviesByID = Dictionary(movies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for key in resume.started(prefix: "movie.") {
                guard let id = Int(key.dropFirst("movie.".count)), let movie = moviesByID[id] else { continue }
                entries.append(LibraryEntry(id: key, title: movie.name, detail: remaining(key), source: .iptv,
                                            image: movie.poster.flatMap(URL.init(string:)), progress: resume.fraction(key),
                                            date: resume.lastPlayed(key) ?? .distantPast, open: .movie(movie)))
            }
            for key in resume.started(prefix: "episode.") {
                let id = String(key.dropFirst("episode.".count))
                guard let (episode, show) = episodeIndex[id] else { continue }
                entries.append(LibraryEntry(id: key, title: show.name, detail: "S\(episode.season) F\(episode.number) · \(remaining(key))", source: .iptv,
                                            image: (episode.image ?? show.cover).flatMap(URL.init(string:)), progress: resume.fraction(key),
                                            date: resume.lastPlayed(key) ?? .distantPast, open: .episode(episode, show)))
            }
        }
        for item in jellyfinResume {
            let date = item.userData?.lastPlayedDate.flatMap { try? Date($0, strategy: .iso8601) } ?? .distantPast
            let left = item.runTimeTicks.map { Double($0 - (item.userData?.playbackPositionTicks ?? 0)) / 10_000_000 }
            entries.append(LibraryEntry(id: "jf." + item.id, title: item.seriesName ?? item.name,
                                        detail: left.map { Self.minutesLeft($0) } ?? "", source: .jellyfin,
                                        image: images.thumb(item).flatMap(URL.init(string:)),
                                        progress: item.userData?.playedPercentage.map { $0 / 100 }, date: date, open: .jellyfin(item)))
        }
        if let resume {
            for recording in recordings where recording.finished || recording.failed {
                let key = ResumeStore.recordingKey(recording.id)
                guard resume.position(key) > 0 else { continue }
                entries.append(LibraryEntry(id: key, title: recording.title,
                                            detail: String(localized: "Recording · \(remaining(key))", bundle: .module),
                                            source: .recording, image: nil, progress: watchedShare(recording),
                                            date: resume.lastPlayed(key) ?? .distantPast, open: .recording(recording.id)))
            }
        }
        return entries.sorted { $0.date > $1.date }
    }

    /// Jellyfin's next episodes.
    public func nextUp() -> [LibraryEntry] {
        jellyfinNextUp.prefix(15).map { item in
            LibraryEntry(id: "jf.next." + item.id, title: item.seriesName ?? item.name, detail: Self.episodeLine(item) ?? item.name,
                         source: .jellyfin, image: (images.backdrop(item) ?? images.poster(item)).flatMap(URL.init(string:)),
                         progress: nil, date: .distantPast, open: .jellyfin(item))
        }
    }

    /// The newest finished recordings.
    public func finishedRecordings() -> [LibraryEntry] {
        recordings.filter(\.finished).sorted { $0.start > $1.start }.prefix(12).map { recording in
            LibraryEntry(id: "rec." + recording.id.uuidString, title: recording.title,
                         detail: "\(recording.channelName) · \(recording.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))",
                         source: .recording, image: channels.first { $0.id == recording.channelId }?.icon.flatMap(URL.init(string:)),
                         progress: resume?.fraction(ResumeStore.recordingKey(recording.id)), date: recording.start, open: .recording(recording.id))
        }
    }

    // MARK: Live rows

    /// The channels of "Jetzt live" and "Heute Abend": favourites, else recently watched, else
    /// the first channels, so a new account has the row too.
    public static func liveChannels(favorites: [LiveChannel], recent: [LiveChannel], all: [LiveChannel]) -> (source: LiveSource, channels: [LiveChannel]) {
        if !favorites.isEmpty { return (.favorites, Array(favorites.prefix(12))) }
        if !recent.isEmpty { return (.recent, Array(recent.prefix(12))) }
        return (.all, Array(all.prefix(12)))
    }

    /// Tonight's prime time (20:00–21:30) on `channels`, one show each, by start; after 21:30
    /// what starts in the next two hours.
    public static func tonight(on channels: [LiveChannel], guide: (Int) -> [EPGEntry], now: Date = Date(),
                               calendar: Calendar = .current) -> (title: String, shows: [(show: EPGEntry, channel: LiveChannel)]) {
        let from = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
        let to = calendar.date(bySettingHour: 21, minute: 30, second: 0, of: now) ?? now
        let primeTime = now < to
        let window = primeTime ? from...to : now...now.addingTimeInterval(2 * 3600)
        var shows: [(show: EPGEntry, channel: LiveChannel)] = []
        for channel in channels {
            if let show = guide(channel.id).first(where: { window.contains($0.start) && $0.end > now }) {
                shows.append((show, channel))
            }
        }
        return (primeTime ? String(localized: "Tonight", bundle: .module) : String(localized: "Coming Up", bundle: .module),
                shows.sorted { $0.show.start < $1.show.start })
    }

    // MARK: Helpers

    /// "S2 F5 · Title" for a Jellyfin episode, nil otherwise (as the apps' players name it).
    public static func episodeLine(_ item: JFItem) -> String? {
        item.type == "Episode" ? "S\(item.parentIndexNumber ?? 0) F\(item.indexNumber ?? 0) · \(item.name)" : nil
    }

    public static func minutesLeft(_ seconds: Double) -> String {
        String(localized: "\(max(1, Int((seconds / 60).rounded()))) min left", bundle: .module)
    }

    /// The share watched (0…1) of a recording.
    public func watchedShare(_ recording: StartRecording) -> Double {
        let duration = recording.recordEnd.timeIntervalSince(recording.recordStart)
        return duration > 0 ? min(1, (resume?.position(ResumeStore.recordingKey(recording.id)) ?? 0) / duration) : 0
    }

    private func remaining(_ key: String) -> String {
        guard let resume, let fraction = resume.fraction(key), fraction > 0 else { return "" }
        let duration = resume.position(key) / fraction
        return Self.minutesLeft(duration - resume.position(key))
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
                     image: images.poster(item).flatMap(URL.init(string:)), progress: nil, date: .distantPast, open: .jellyfin(item))
    }
}
