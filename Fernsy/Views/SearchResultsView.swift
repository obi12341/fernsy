import Combine
import FernsyCore
import FernsyPlayer
import SwiftUI

/// The hits of one query, as the items themselves, best first.
struct SearchResults {
    var query = ""
    var channels: [LiveChannel] = []
    /// Shows on the favourite channels that run now or later (search-favorite-shows).
    var shows: [ShowSearch.Hit] = []
    var movies: [Movie] = []
    var series: [Series] = []
    var recordings: [Recording] = []
    var jellyfinFilms: [JFItem] = []
    var jellyfinSeries: [JFItem] = []

    var isEmpty: Bool {
        channels.isEmpty && shows.isEmpty && movies.isEmpty && series.isEmpty && recordings.isEmpty && jellyfinFilms.isEmpty && jellyfinSeries.isEmpty
    }
}

/// Searches everything the toolbar search covers. The index is rebuilt in the background when a
/// source changes while a query is typed; a query runs 150 ms after the last keystroke, off the
/// main thread, and a newer one cancels it.
@MainActor
final class SearchModel: ObservableObject {
    @Published private(set) var results: SearchResults?

    /// The lists the index points into, as they were when it was built.
    private struct Snapshot {
        var channels: [LiveChannel] = []
        var movies: [Movie] = []
        var series: [Series] = []
        var recordings: [Recording] = []
        var jellyfinFilms: [JFItem] = []
        var jellyfinSeries: [JFItem] = []
        var index = SearchIndex(entries: [])
        /// The visible favourites (hidden channels and adult categories already left out).
        var favorites: [LiveChannel] = []
    }

    private var snapshot: Snapshot?
    /// The favourites' loaded guides as folded titles; rebuilt with the snapshot and after the
    /// guides were loaded for a search.
    private var shows = ShowSearch(channels: [], guides: [:])
    /// Whether this search (until the field is cleared) already asked for the favourites' guides.
    private var guidesRequested = false
    private var guideTask: Task<Void, Never>?
    private var stale = true
    private var query = ""
    private var searchTask: Task<Void, Never>?
    private var rebuildTask: Task<Void, Never>?
    private var observers: Set<AnyCancellable> = []
    private weak var app: AppModel?
    private weak var jellyfin: JellyfinStore?
    private weak var recorder: Recorder?

    func attach(app: AppModel, jellyfin: JellyfinStore, recorder: Recorder) {
        guard self.app == nil else { return }
        self.app = app
        self.jellyfin = jellyfin
        self.recorder = recorder
        // Any change of a source (catalog, visibility, settings, library, recordings) makes the
        // index stale; while a query is shown, it is rebuilt shortly after.
        Publishers.Merge3(app.objectWillChange, jellyfin.objectWillChange, recorder.objectWillChange)
            .sink { [weak self] _ in
                guard let self else { return }
                stale = true
                if !query.isEmpty { scheduleRebuild() }
            }
            .store(in: &observers)
    }

    func setQuery(_ newQuery: String) {
        query = newQuery
        searchTask?.cancel()
        let needle = makeSearchKey(newQuery.trimmingCharacters(in: .whitespaces))
        guard !needle.isEmpty else {
            results = nil
            guidesRequested = false
            return
        }
        loadFavoriteGuides()
        if stale || snapshot == nil {
            scheduleRebuild()
        } else {
            search(needle, delay: .milliseconds(150))
        }
    }

    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(self?.snapshot == nil ? 0 : 300))
            guard let self, !Task.isCancelled else { return }
            await rebuild()
            let needle = makeSearchKey(query.trimmingCharacters(in: .whitespaces))
            if !needle.isEmpty { search(needle, delay: .zero) }
        }
    }

    private func rebuild() async {
        guard let app, let jellyfin, let recorder else { return }
        stale = false
        // The same exclusions as the sections: hidden channels and categories, adult categories.
        let showAdult = app.showAdult
        let adultLive = app.hiddenCategoryIDs(app.liveCategories)
        let adultMovies = app.hiddenCategoryIDs(app.movieCategories)
        let adultSeries = app.hiddenCategoryIDs(app.seriesCategories)
        let visibility = app.visibility
        let favoriteIDs = app.filteredChannels(categoryID: favoriteChannelsID, query: "").map(\.id)
        var next = Snapshot(channels: app.channels, movies: app.movies, series: app.series,
                            recordings: recorder.recordings,
                            jellyfinFilms: jellyfin.items(.films), jellyfinSeries: jellyfin.items(.series))
        next = await Task.detached(priority: .userInitiated) { () -> Snapshot in
            var snapshot = next
            snapshot.channels = snapshot.channels.filter { channel in
                let category = channel.categoryId ?? ""
                return !visibility.hiddenChannels.contains(channel.id) && !visibility.hiddenCategories.contains(category)
                    && (showAdult || (!channel.isAdult && !adultLive.contains(category)))
            }
            let visible = Dictionary(snapshot.channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            snapshot.favorites = favoriteIDs.compactMap { visible[$0] }
            if !showAdult {
                snapshot.movies = snapshot.movies.filter { !$0.isAdult && !adultMovies.contains($0.categoryId ?? "") }
                snapshot.series = snapshot.series.filter { !adultSeries.contains($0.categoryId ?? "") }
            }
            var entries: [SearchEntry] = []
            entries.reserveCapacity(snapshot.channels.count + snapshot.movies.count + snapshot.series.count)
            for (i, item) in snapshot.channels.enumerated() { entries.append(SearchEntry(source: .channels, index: i, key: item.searchKey)) }
            for (i, item) in snapshot.movies.enumerated() { entries.append(SearchEntry(source: .movies, index: i, key: item.searchKey)) }
            for (i, item) in snapshot.series.enumerated() { entries.append(SearchEntry(source: .series, index: i, key: item.searchKey)) }
            for (i, item) in snapshot.recordings.enumerated() {
                entries.append(SearchEntry(source: .recordings, index: i, key: makeSearchKey(item.title + " " + item.channelName)))
            }
            for (i, item) in snapshot.jellyfinFilms.enumerated() { entries.append(SearchEntry(source: .jellyfinFilms, index: i, key: makeSearchKey(item.name))) }
            for (i, item) in snapshot.jellyfinSeries.enumerated() { entries.append(SearchEntry(source: .jellyfinSeries, index: i, key: makeSearchKey(item.name))) }
            snapshot.index = SearchIndex(entries: entries)
            return snapshot
        }.value
        snapshot = next
        rebuildShows()
    }

    /// The favourites' shows from the guides loaded now.
    private func rebuildShows() {
        guard let app, let snapshot else { return }
        let favorites = Array(snapshot.favorites.prefix(ShowSearch.channelLimit))
        let guides = Dictionary(favorites.map { ($0.id, app.epg.guide($0.id).entries ?? []) }, uniquingKeysWith: { first, _ in first })
        shows = ShowSearch(channels: favorites, guides: guides)
    }

    /// Once per search: loads the favourites' full guides in the background (`EPGStore` skips
    /// fresh ones and reads its disk cache first; the channel list alone only has now and next)
    /// and searches again when they are in. Typing never waits for it.
    private func loadFavoriteGuides() {
        guard !guidesRequested, let app else { return }
        guidesRequested = true
        let missing = app.filteredChannels(categoryID: favoriteChannelsID, query: "")
            .prefix(ShowSearch.channelLimit).map(\.id)
        guard !missing.isEmpty else { return }
        guideTask?.cancel()
        guideTask = Task { [weak self] in
            let started = Date()
            await app.epg.load(missing, client: app.client, timeout: 20)
            guard let self, !Task.isCancelled else { return }
            AppLog.detail(.app, "search: guides of \(missing.count) favourites loaded in \(Int(-started.timeIntervalSinceNow * 1000)) ms")
            rebuildShows()
            let needle = makeSearchKey(query.trimmingCharacters(in: .whitespaces))
            if !needle.isEmpty { search(needle, delay: .zero) }
        }
    }

    private func search(_ needle: String, delay: Duration) {
        searchTask?.cancel()
        guard let snapshot else { return }
        let query = query
        let shows = shows
        searchTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            let started = Date()
            let (hits, showHits) = await Task.detached(priority: .userInitiated) { (snapshot.index.search(needle), shows.search(needle)) }.value
            guard let self, !Task.isCancelled else { return }
            var results = SearchResults(query: query)
            results.channels = (hits[.channels] ?? []).map { snapshot.channels[$0] }
            results.shows = showHits
            results.movies = (hits[.movies] ?? []).map { snapshot.movies[$0] }
            results.series = (hits[.series] ?? []).map { snapshot.series[$0] }
            results.recordings = (hits[.recordings] ?? []).map { snapshot.recordings[$0] }
            results.jellyfinFilms = (hits[.jellyfinFilms] ?? []).map { snapshot.jellyfinFilms[$0] }
            results.jellyfinSeries = (hits[.jellyfinSeries] ?? []).map { snapshot.jellyfinSeries[$0] }
            AppLog.detail(.app, "search \"\(query)\": \(hits.values.reduce(0) { $0 + $1.count }) hits of \(snapshot.index.entries.count), \(showHits.count) shows on \(snapshot.favorites.count) favourites, in \(Int(-started.timeIntervalSinceNow * 1000)) ms")
            self.results = results
        }
    }
}

private let posterColumns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20, alignment: .top)]

/// The toolbar search's results: one group per source with hits, each showing its first hits.
struct SearchResultsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var jellyfin: JellyfinStore
    @EnvironmentObject private var recorder: Recorder
    let results: SearchResults?
    /// Leaves the search for Live TV's guide of the favourites.
    var showInGuide: () -> Void = {}

    /// Groups the user expanded with "show all".
    @State private var expanded: Set<SearchSource> = []
    @State private var showsExpanded = false
    /// A later show the user clicked: asked whether to record it.
    @State private var asked: ShowSearch.Hit?

    private static let rowLimit = 20
    private static let posterLimit = 12

    var body: some View {
        Group {
            if let results {
                if results.isEmpty {
                    ContentUnavailableView.search(text: results.query)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 28) {
                            groups(results)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .onChange(of: results?.query) { _, _ in
            expanded = []
            showsExpanded = false
        }
        #if DEBUG
        .onChange(of: results?.shows.count) { _, _ in debugSelectShow() }
        #endif
        .confirmationDialog(asked.map { recordQuestion($0) } ?? "", isPresented: Binding(get: { asked != nil }, set: { if !$0 { asked = nil } }),
                            presenting: asked) { hit in
            Button("Record") { recorder.schedule(hit.entry, on: hit.channel).present() }
            ServerRecordItem(app: app, entry: hit.entry, channel: hit.channel)
            Button("Cancel", role: .cancel) {}
        } message: { hit in
            Text(verbatim: ShowHitRow.caption(hit))
        }
        .navigationTitle("Search")
    }

    #if DEBUG
    /// IPTV_TESTSHOWSELECT=running|later|ask: selects the first running or later show hit as a
    /// click does; for a later one it then answers "Record", with `ask` it leaves the record
    /// question open for a screenshot (the Mac app has no UI test target).
    private func debugSelectShow() {
        guard let mode = ProcessInfo.processInfo.environment["IPTV_TESTSHOWSELECT"], let shows = results?.shows,
              let hit = shows.first(where: { ($0.entry.start <= Date()) == (mode == "running") }) else { return }
        debugLog("[test] selecting show \"\(hit.entry.title)\" on \(hit.channel.id) (\(mode))")
        select(hit)
        if asked != nil, mode != "ask" {
            debugLog("[test] asked: \(recordQuestion(hit)) – answering Record")
            recorder.schedule(hit.entry, on: hit.channel).present()
            asked = nil
            debugLog("[test] planned: \(planned(hit) != nil)")
        }
    }
    #endif

    private func recordQuestion(_ hit: ShowSearch.Hit) -> String {
        String(localized: "Record “\(hit.entry.title)”?")
    }

    /// Running: play the channel. Later: ask to record it, or nothing when it is planned (the
    /// context menu removes it).
    private func select(_ hit: ShowSearch.Hit) {
        if hit.entry.start <= Date() {
            app.play(hit.channel)
        } else if planned(hit) == nil {
            asked = hit
        }
    }

    private func planned(_ hit: ShowSearch.Hit) -> Recording? {
        recorder.recording(channelId: hit.channel.id, entry: hit.entry).flatMap { $0.isUpcomingOrRunning ? $0 : nil }
    }

    @ViewBuilder
    private func showsGroup(_ shows: [ShowSearch.Hit]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Shows").font(.title2.weight(.semibold))
            Text("\(shows.count)").foregroundStyle(.secondary).monospacedDigit()
            Text("on your favorites").foregroundStyle(.secondary)
            Spacer()
            if shows.count > Self.rowLimit {
                Button(showsExpanded ? "Show less" : "Show all (\(shows.count))") { showsExpanded.toggle() }
                    .buttonStyle(.link)
            }
        }
        VStack(spacing: 2) {
            ForEach(showsExpanded ? shows : Array(shows.prefix(Self.rowLimit)), id: \.entry.id) { hit in
                let plan = planned(hit)
                Button { select(hit) } label: {
                    ShowHitRow(hit: hit, isPlanned: plan != nil || app.cloud.server.pendingOrder(channelId: hit.channel.id, start: hit.entry.start) != nil)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.show.\(hit.channel.id).\(Int(hit.entry.start.timeIntervalSince1970))")
                .contextMenu {
                    Button("Play Channel") { app.play(hit.channel) }
                    if let plan {
                        Button(plan.status == .recording ? "Stop Recording" : "Remove Recording") { recorder.stop(plan.id) }
                    } else {
                        Button("Record") { recorder.schedule(hit.entry, on: hit.channel).present() }
                    }
                    ServerRecordItem(app: app, entry: hit.entry, channel: hit.channel)
                    Button("Show in Guide", action: showInGuide)
                }
            }
        }
    }

    @ViewBuilder
    private func groups(_ results: SearchResults) -> some View {
        if !results.channels.isEmpty {
            header("Channels", source: .channels, total: results.channels.count, limit: Self.rowLimit)
            VStack(spacing: 2) {
                ForEach(shown(results.channels, .channels, Self.rowLimit)) { channel in
                    Button { app.play(channel) } label: {
                        ChannelRow(channel: channel, isPlaying: isPlaying(channel))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Play") { app.play(channel) }
                        Button(app.isFavorite("live:\(channel.id)") ? "Remove from Favorites" : "Add to Favorites") {
                            app.toggleFavorite("live:\(channel.id)")
                        }
                    }
                }
            }
        }
        if !results.shows.isEmpty {
            showsGroup(results.shows)
        }
        if !results.movies.isEmpty {
            header("Movies", source: .movies, total: results.movies.count, limit: Self.posterLimit)
            LazyVGrid(columns: posterColumns, spacing: 24) {
                ForEach(shown(results.movies, .movies, Self.posterLimit)) { movie in
                    NavigationLink(value: movie) {
                        PosterCard(title: movie.name, imageURL: movie.poster, rating: movie.rating,
                                   isFavorite: app.isFavorite("movie:\(movie.id)"))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Play") { app.play(movie) }
                    }
                }
            }
        }
        if !results.series.isEmpty {
            header("Series", source: .series, total: results.series.count, limit: Self.posterLimit)
            LazyVGrid(columns: posterColumns, spacing: 24) {
                ForEach(shown(results.series, .series, Self.posterLimit)) { show in
                    NavigationLink(value: show) {
                        PosterCard(title: show.name, imageURL: show.cover, rating: show.rating,
                                   isFavorite: app.isFavorite("series:\(show.id)"))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !results.jellyfinFilms.isEmpty {
            header("Jellyfin Movies", source: .jellyfinFilms, total: results.jellyfinFilms.count, limit: Self.posterLimit)
            jellyfinGrid(shown(results.jellyfinFilms, .jellyfinFilms, Self.posterLimit))
        }
        if !results.jellyfinSeries.isEmpty {
            header("Jellyfin Series", source: .jellyfinSeries, total: results.jellyfinSeries.count, limit: Self.posterLimit)
            jellyfinGrid(shown(results.jellyfinSeries, .jellyfinSeries, Self.posterLimit))
        }
        if !results.recordings.isEmpty {
            header("Recordings", source: .recordings, total: results.recordings.count, limit: Self.rowLimit)
            VStack(spacing: 6) {
                ForEach(shown(results.recordings, .recordings, Self.rowLimit)) { RecordingRow(recording: $0) }
            }
        }
    }

    private func jellyfinGrid(_ items: [JFItem]) -> some View {
        LazyVGrid(columns: posterColumns, spacing: 24) {
            ForEach(items) { item in
                NavigationLink(value: item) { JellyfinPoster(item: item) }
                    .buttonStyle(.plain)
                    .contextMenu { JellyfinItemMenu(item: item) }
            }
        }
    }

    private func header(_ title: LocalizedStringKey, source: SearchSource, total: Int, limit: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.weight(.semibold))
            Text("\(total)").foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            if total > limit {
                Button(expanded.contains(source) ? "Show less" : "Show all (\(total))") {
                    if expanded.contains(source) { expanded.remove(source) } else { expanded.insert(source) }
                }
                .buttonStyle(.link)
            }
        }
    }

    private func shown<T>(_ items: [T], _ source: SearchSource, _ limit: Int) -> [T] {
        expanded.contains(source) ? items : Array(items.prefix(limit))
    }

    private func isPlaying(_ channel: LiveChannel) -> Bool {
        if case .live(let id, _)? = app.nowPlaying?.kind { return id == channel.id }
        return false
    }
}

/// A show in the search results: channel logo, title, "Das Erste · Heute 20:15–21:45", whether
/// it runs now and whether a recording is planned.
struct ShowHitRow: View {
    let hit: ShowSearch.Hit
    let isPlanned: Bool

    var body: some View {
        let runs = hit.entry.start <= Date()
        HStack(spacing: 12) {
            LogoTile(url: hit.channel.icon, name: hit.channel.displayName, width: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(hit.entry.title).font(.body.weight(.medium)).lineLimit(1)
                    if runs { StatusBadge(kind: .live) }
                    if isPlanned { StatusBadge(kind: .scheduled) }
                }
                Text(verbatim: Self.caption(hit)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// "Das Erste · Heute 20:15–21:45".
    static func caption(_ hit: ShowSearch.Hit) -> String {
        let entry = hit.entry
        let times = "\(entry.start.formatted(date: .omitted, time: .shortened))–\(entry.end.formatted(date: .omitted, time: .shortened))"
        let day = Calendar.current.isDateInToday(entry.start) ? String(localized: "Today")
            : Calendar.current.isDateInTomorrow(entry.start) ? String(localized: "Tomorrow")
            : entry.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(hit.channel.displayName) · \(day) \(times)"
    }
}
