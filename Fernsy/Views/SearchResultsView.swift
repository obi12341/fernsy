import Combine
import SwiftUI

/// The hits of one query, as the items themselves, best first.
struct SearchResults {
    var query = ""
    var channels: [LiveChannel] = []
    var movies: [Movie] = []
    var series: [Series] = []
    var recordings: [Recording] = []
    var jellyfinFilms: [JFItem] = []
    var jellyfinSeries: [JFItem] = []

    var isEmpty: Bool {
        channels.isEmpty && movies.isEmpty && series.isEmpty && recordings.isEmpty && jellyfinFilms.isEmpty && jellyfinSeries.isEmpty
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
    }

    private var snapshot: Snapshot?
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
            return
        }
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
    }

    private func search(_ needle: String, delay: Duration) {
        searchTask?.cancel()
        guard let snapshot else { return }
        let query = query
        searchTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            let started = Date()
            let hits = await Task.detached(priority: .userInitiated) { snapshot.index.search(needle) }.value
            guard let self, !Task.isCancelled else { return }
            var results = SearchResults(query: query)
            results.channels = (hits[.channels] ?? []).map { snapshot.channels[$0] }
            results.movies = (hits[.movies] ?? []).map { snapshot.movies[$0] }
            results.series = (hits[.series] ?? []).map { snapshot.series[$0] }
            results.recordings = (hits[.recordings] ?? []).map { snapshot.recordings[$0] }
            results.jellyfinFilms = (hits[.jellyfinFilms] ?? []).map { snapshot.jellyfinFilms[$0] }
            results.jellyfinSeries = (hits[.jellyfinSeries] ?? []).map { snapshot.jellyfinSeries[$0] }
            AppLog.detail(.app, "search \"\(query)\": \(hits.values.reduce(0) { $0 + $1.count }) hits of \(snapshot.index.entries.count) in \(Int(-started.timeIntervalSinceNow * 1000)) ms")
            self.results = results
        }
    }
}

private let posterColumns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20, alignment: .top)]

/// The toolbar search's results: one group per source with hits, each showing its first hits.
struct SearchResultsView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var jellyfin: JellyfinStore
    let results: SearchResults?

    /// Groups the user expanded with "show all".
    @State private var expanded: Set<SearchSource> = []

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
        .onChange(of: results?.query) { _, _ in expanded = [] }
        .navigationTitle("Search")
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
