import FernsyCore
import FernsyPlayer
import Foundation

/// A film, an episode or a Jellyfin item to play (tvos-library).
enum VODItem: Equatable {
    case movie(Movie)
    case episode(Episode, Series)
    case jellyfin(JFItem)

    var title: String {
        switch self {
        case .movie(let movie): movie.name
        case .episode(_, let series): series.name
        case .jellyfin(let item): item.seriesName ?? item.name
        }
    }

    var subtitle: String? {
        switch self {
        case .movie: nil
        case .episode(let episode, _): "S\(episode.season) F\(episode.number) · \(episode.title)"
        case .jellyfin(let item):
            item.type == "Episode" ? "S\(item.parentIndexNumber ?? 0) F\(item.indexNumber ?? 0) · \(item.name)" : nil
        }
    }

    /// The resume key of IPTV items (Jellyfin keeps positions on the server).
    var resumeKey: String? {
        switch self {
        case .movie(let movie): ResumeStore.movieKey(movie.id)
        case .episode(let episode, _): "episode.\(episode.id)"
        case .jellyfin: nil
        }
    }
}

/// One entry of Start's "Continue Watching" and "Recently Added" rows, from any source.
struct LibraryEntry: Identifiable {
    enum Source { case iptv, jellyfin, recording }

    let id: String
    let title: String
    let detail: String
    let source: Source
    let image: URL?
    /// 0…1 watched, nil when not started.
    let progress: Double?
    let date: Date
    let open: Target

    enum Target {
        case movie(Movie), series(Series), episode(Episode, Series), jellyfin(JFItem), recording(Recording)
    }
}

/// Films and series of the IPTV account and Jellyfin, resume positions, Start's rows and
/// on-demand playback on Apple TV, with the Mac's rules (FernsyCore, FernsyPlayer).
extension TVModel {
    // MARK: IPTV catalog

    /// Loads the provider's film and series lists (cached in Caches like the live catalog); a
    /// kind that is switched off is neither downloaded nor kept (stored as `[]`).
    func loadLibraryCatalog() async {
        guard let client, let credentials, !libraryLoading else { return }
        libraryLoading = true
        defer { libraryLoading = false }
        let url = Self.libraryCacheURL(credentials.accountKey)
        if movies.isEmpty, series.isEmpty, let data = try? Data(contentsOf: url), let cache = try? JSONDecoder().decode(LibraryCache.self, from: data) {
            apply(cache)
        }
        do {
            let films = showsIPTVMovies, shows = showsIPTVSeries
            let cache = LibraryCache(movieCategories: films ? try await client.catalog(.vodCategories) : LibraryCache.none,
                                     movies: films ? try await client.catalog(.vodStreams) : LibraryCache.none,
                                     seriesCategories: shows ? try await client.catalog(.seriesCategories) : LibraryCache.none,
                                     series: shows ? try await client.catalog(.series) : LibraryCache.none)
            apply(cache)
            write(cache, to: url)
            AppLog.info(.catalog, "\(movies.count) films, \(series.count) series")
        } catch {
            AppLog.error(.catalog, "films and series failed: \(error.localizedDescription)")
        }
    }

    /// Settings › IPTV Account, here or synced from another device. Off: the kind is emptied and
    /// dropped from the cache. On: it is downloaded at once, after a download that is running.
    func librarySwitched(movies kind: Bool, on: Bool) {
        AppLog.info(.catalog, "\(kind ? "films" : "series") switched \(on ? "on" : "off")")
        guard on else {
            if kind { movieCategories = []; movies = []; movieInfo = [:] } else { seriesCategories = []; series = []; seriesInfo = [:] }
            updateLibraryCache { cache in
                if kind { cache.movieCategories = LibraryCache.none; cache.movies = LibraryCache.none } else { cache.seriesCategories = LibraryCache.none; cache.series = LibraryCache.none }
            }
            return
        }
        Task {
            while libraryLoading { try? await Task.sleep(for: .milliseconds(200)) }
            guard let client, kind ? showsIPTVMovies : showsIPTVSeries else { return }
            libraryLoading = true
            defer { libraryLoading = false }
            do {
                let categories = try await client.catalog(kind ? .vodCategories : .seriesCategories)
                let items = try await client.catalog(kind ? .vodStreams : .series)
                guard kind ? showsIPTVMovies : showsIPTVSeries else { return }
                if let cache = updateLibraryCache({ cache in
                    if kind { cache.movieCategories = categories; cache.movies = items } else { cache.seriesCategories = categories; cache.series = items }
                }) { apply(cache) }
                AppLog.info(.catalog, "\(kind ? "films" : "series") downloaded: \(kind ? movies.count : series.count)")
            } catch {
                AppLog.error(.catalog, "download after switching on failed: \(error.localizedDescription)")
            }
        }
    }

    /// The switch as stored; test runs (no keychain) and IPTV_SHOWMOVIES / IPTV_SHOWSERIES=0|1
    /// keep it in memory.
    static func librarySwitch(_ key: String, env: String) -> Bool {
        #if DEBUG
        if let value = ProcessInfo.processInfo.environment[env] { return value == "1" }
        #endif
        return skipKeychain ? true : UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    func storeLibrarySwitch(_ value: Bool, _ key: String) {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["IPTV_SHOWMOVIES"] != nil || env["IPTV_SHOWSERIES"] != nil { return }
        #endif
        if !Self.skipKeychain { UserDefaults.standard.set(value, forKey: key) }
    }

    private func apply(_ cache: LibraryCache) {
        #if DEBUG
        let cache = Self.debugEnlarged(cache)
        #endif
        let decoder = JSONDecoder()
        let allMovieCategories = showsIPTVMovies ? (try? decoder.decode([XCategory].self, from: cache.movieCategories)) ?? [] : []
        movieCategories = allMovieCategories.filter { !LiveRules.isAdultCategory($0) }
        let adultMovies = Set(allMovieCategories.filter(LiveRules.isAdultCategory).map(\.id))
        movies = (showsIPTVMovies ? (try? decoder.decode([Movie].self, from: cache.movies)) ?? [] : []).filter { !$0.isAdult && !adultMovies.contains($0.categoryId ?? "") }
        let allSeriesCategories = showsIPTVSeries ? (try? decoder.decode([XCategory].self, from: cache.seriesCategories)) ?? [] : []
        seriesCategories = allSeriesCategories.filter { !LiveRules.isAdultCategory($0) }
        let adultSeries = Set(allSeriesCategories.filter(LiveRules.isAdultCategory).map(\.id))
        series = (showsIPTVSeries ? (try? decoder.decode([Series].self, from: cache.series)) ?? [] : []).filter { !adultSeries.contains($0.categoryId ?? "") }
    }

    #if DEBUG
    /// IPTV_TESTBIGCATALOG=<n>: the films and series repeated with new ids up to n each, in memory,
    /// so the simulator has a provider-sized catalog without a real provider (tvos-start-scrolling).
    private static func debugEnlarged(_ cache: LibraryCache) -> LibraryCache {
        guard let target = ProcessInfo.processInfo.environment["IPTV_TESTBIGCATALOG"].flatMap(Int.init) else { return cache }
        func enlarged(_ data: Data, id: String, date: String) -> Data {
            guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !items.isEmpty else { return data }
            var out = items
            var copy = 1
            while out.count < target {
                for item in items where out.count < target {
                    var item = item
                    let base = (item[id] as? Int) ?? Int("\(item[id] ?? 0)") ?? 0
                    item[id] = base + copy * 1_000_000
                    item["name"] = "\(item["name"] ?? "") \(copy)"
                    let stamp = (item[date] as? Int) ?? Int("\(item[date] ?? 0)") ?? 0
                    item[date] = "\(max(0, stamp - copy * 60))"
                    out.append(item)
                }
                copy += 1
            }
            return (try? JSONSerialization.data(withJSONObject: out)) ?? data
        }
        var cache = cache
        cache.movies = enlarged(cache.movies, id: "stream_id", date: "added")
        cache.series = enlarged(cache.series, id: "series_id", date: "last_modified")
        return cache
    }
    #endif

    /// Changes the stored lists of the signed-in account and returns them.
    @discardableResult
    private func updateLibraryCache(_ change: (inout LibraryCache) -> Void) -> LibraryCache? {
        guard let credentials else { return nil }
        let url = Self.libraryCacheURL(credentials.accountKey)
        var cache = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(LibraryCache.self, from: $0) }
            ?? LibraryCache(movieCategories: LibraryCache.none, movies: LibraryCache.none, seriesCategories: LibraryCache.none, series: LibraryCache.none)
        change(&cache)
        write(cache, to: url)
        return cache
    }

    private func write(_ cache: LibraryCache, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(cache).write(to: url, options: .atomic)
    }

    private static func libraryCacheURL(_ accountKey: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fernsy/\(accountKey)/vod-catalog.json")
    }

    func movieDetails(_ movie: Movie) async -> MovieDetails? {
        if let cached = movieInfo[movie.id] { return cached }
        guard let details = try? await client?.movieDetails(movie.id) else { return nil }
        movieInfo[movie.id] = details
        return details
    }

    func seriesDetails(_ series: Series) async -> SeriesInfo? {
        if let cached = seriesInfo[series.id] { return cached }
        guard let info = try? await client?.seriesInfo(series.id) else { return nil }
        seriesInfo[series.id] = info
        return info
    }

    // MARK: Favourites, resume, watched

    func isFavorite(movie: Movie) -> Bool { favorites.contains(LibraryRules.favoriteKey(movie: movie.id)) }
    func isFavorite(series: Series) -> Bool { favorites.contains(LibraryRules.favoriteKey(series: series.id)) }

    func toggleFavorite(key: String) {
        if favorites.contains(key) { favorites.remove(key) } else { favorites.insert(key) }
        if !Self.skipKeychain { UserDefaults.standard.set(Array(favorites), forKey: LiveRules.favoritesKey) }
    }

    /// The next episode to watch: the first not watched after the last watched or started one.
    func nextEpisode(of series: Series, in info: SeriesInfo) -> Episode? {
        let all = info.seasons.keys.sorted().flatMap { info.seasons[$0] ?? [] }
        if let started = all.first(where: { resume.position("episode.\($0.id)") > 0 }) { return started }
        let lastWatched = all.lastIndex { resume.isWatched("episode.\($0.id)") }
        return lastWatched.map { all.index(after: $0) < all.count ? all[all.index(after: $0)] : all[$0] } ?? all.first
    }

    // MARK: Start

    /// Partly watched films and episodes of the IPTV account, Jellyfin items and recordings,
    /// newest first (design C).
    var continueWatching: [LibraryEntry] {
        var entries: [LibraryEntry] = []
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
        for item in jellyfin.resume {
            let date = item.userData?.lastPlayedDate.flatMap { try? Date($0, strategy: .iso8601) } ?? .distantPast
            let left = item.runTimeTicks.map { Double($0 - (item.userData?.playbackPositionTicks ?? 0)) / 10_000_000 }
            entries.append(LibraryEntry(id: "jf." + item.id, title: item.seriesName ?? item.name,
                                        detail: left.map { String(localized: "\(max(1, Int(($0 / 60).rounded()))) min left") } ?? "", source: .jellyfin,
                                        image: jellyfin.thumbURL(item).flatMap(URL.init(string:)),
                                        progress: item.userData?.playedPercentage.map { $0 / 100 }, date: date, open: .jellyfin(item)))
        }
        for recording in recorder.recordings where recording.status == .done || recording.status == .failed {
            let key = ResumeStore.recordingKey(recording.id)
            guard resume.position(key) > 0 else { continue }
            entries.append(LibraryEntry(id: key, title: recording.title, detail: String(localized: "Recording · \(remaining(key))"),
                                        source: .recording, image: nil, progress: watchedShare(recording),
                                        date: resume.lastPlayed(key) ?? .distantPast, open: .recording(recording)))
        }
        return entries.sorted { $0.date > $1.date }
    }

    /// The newest IPTV films and series and Jellyfin items, interleaved by date.
    var recentlyAdded: [LibraryEntry] {
        var entries: [LibraryEntry] = []
        for movie in newestMovies {
            entries.append(LibraryEntry(id: "movie:\(movie.id)", title: movie.name, detail: "IPTV", source: .iptv,
                                        image: movie.poster.flatMap(URL.init(string:)), progress: nil,
                                        date: Date(timeIntervalSince1970: Double(movie.added)), open: .movie(movie)))
        }
        for show in newestSeries {
            entries.append(LibraryEntry(id: "series:\(show.id)", title: show.name, detail: "IPTV", source: .iptv,
                                        image: show.cover.flatMap(URL.init(string:)), progress: nil,
                                        date: Date(timeIntervalSince1970: Double(show.lastModified)), open: .series(show)))
        }
        for item in jellyfin.latestFilms + jellyfin.latestSeries {
            let date = item.dateCreated.flatMap { try? Date($0, strategy: .iso8601) } ?? .distantPast
            entries.append(LibraryEntry(id: "jf." + item.id, title: item.name, detail: "Jellyfin", source: .jellyfin,
                                        image: jellyfin.posterURL(item).flatMap(URL.init(string:)), progress: nil, date: date, open: .jellyfin(item)))
        }
        return Array(entries.sorted { $0.date > $1.date }.prefix(24))
    }

    private func remaining(_ key: String) -> String {
        guard let fraction = resume.fraction(key), fraction > 0 else { return "" }
        let duration = resume.position(key) / fraction
        let minutes = max(1, Int(((duration - resume.position(key)) / 60).rounded()))
        return String(localized: "\(minutes) min left")
    }

    /// Episodes seen in loaded series, by id, so "Continue Watching" can name them.
    var episodeIndex: [String: (Episode, Series)] {
        var index: [String: (Episode, Series)] = [:]
        for (id, info) in seriesInfo {
            guard let show = seriesByID[id] else { continue }
            for episode in info.seasons.values.flatMap({ $0 }) { index[episode.id] = (episode, show) }
        }
        return index
    }

    // MARK: Playback

    /// Plays a film, an episode or a Jellyfin item full screen, from where it stopped unless
    /// `fromStart`.
    func play(_ item: VODItem, fromStart: Bool = false) {
        stop()
        stopPreview()
        playingVOD = item
        switch item {
        case .movie(let movie):
            guard let url = client?.movieURL(movie) else { return }
            engine.load(url: url, isLive: false, startAt: fromStart ? 0 : resume.position(item.resumeKey ?? ""))
        case .episode(let episode, _):
            guard let url = client?.episodeURL(episode) else { return }
            engine.load(url: url, isLive: false, startAt: fromStart ? 0 : resume.position(item.resumeKey ?? ""))
        case .jellyfin(let jfItem):
            Task { @MainActor in
                guard let playback = await JellyfinPlayback.make(itemId: jfItem.id, store: jellyfin, engine: engine),
                      playingVOD == item else { return }
                jellyfinPlayback = playback
                let start = fromStart ? 0 : Double(jfItem.userData?.playbackPositionTicks ?? 0) / 10_000_000
                playback.start(at: start)
            }
        }
        AppLog.info(.player, "play \(item.title)")
    }

    /// Ends on-demand playback: IPTV positions are kept here, Jellyfin reports to the server.
    func stopVOD() {
        guard let item = playingVOD else { return }
        if let key = item.resumeKey {
            if resume.save(key, position: engine.progress.position, duration: engine.progress.duration) {
                AppLog.detail(.player, "watched \(key)")
            }
        }
        jellyfinPlayback?.stop()
        jellyfinPlayback = nil
        engine.stop()
        playingVOD = nil
        if case .jellyfin(let jfItem) = item {
            Task { await jellyfin.refreshAfterPlayback(jfItem.id) }
        }
    }

    /// What follows the playing episode: Jellyfin's next episode, or the next IPTV episode.
    var nextAfterPlaying: VODItem? {
        switch playingVOD {
        case .jellyfin: return jellyfinPlayback?.nextEpisode.map { .jellyfin($0) }
        case .episode(let episode, let show):
            guard let info = seriesInfo[show.id] else { return nil }
            let all = info.seasons.keys.sorted().flatMap { info.seasons[$0] ?? [] }
            guard let index = all.firstIndex(of: episode), all.index(after: index) < all.count else { return nil }
            return .episode(all[all.index(after: index)], show)
        default: return nil
        }
    }
}

/// The provider's film and series lists as delivered, in Caches.
struct LibraryCache: Codable {
    /// A list of a kind that is switched off.
    static let none = Data("[]".utf8)

    var movieCategories: Data
    var movies: Data
    var seriesCategories: Data
    var series: Data
}
