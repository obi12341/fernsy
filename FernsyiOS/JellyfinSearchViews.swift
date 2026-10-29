import FernsyCore
import FernsyPlayer
import SwiftUI

/// Jellyfin (ios-app "Jellyfin"): the server's state and the views Overview, Movies, Series and
/// Libraries, as in the Apple TV app.
struct JellyfinView: View {
    enum Page: CaseIterable { case overview, films, series, libraries }

    @EnvironmentObject private var model: TVModel
    @State private var page: Page = .overview
    @State private var library: JFItem?
    @State private var overview = JellyfinOverview()
    @State private var spotlight: JFItem?
    @State private var recentSpotlights: [String] = []

    var body: some View {
        let store = model.jellyfin
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 6) {
                    Circle().fill(store.isOffline ? TVTheme.warning : Color(hex: 0x4CD07D)).frame(width: 8, height: 8)
                    Text(verbatim: "\(store.session?.serverName ?? "") · \(store.isOffline ? String(localized: "not reachable") : String(localized: "connected"))")
                }
                .font(.subheadline).foregroundStyle(TVTheme.secondary)
                .padding(.horizontal, 16)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("jellyfin.state")
                Picker("View", selection: Binding(get: { page }, set: { page = $0; library = nil })) {
                    ForEach(Page.allCases, id: \.self) { value in Text(Self.title(value)).tag(value) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("jellyfin.view")
                if store.isOffline {
                    Text("The server cannot be reached. Showing what was loaded last.")
                        .font(.subheadline).foregroundStyle(TVTheme.warning).padding(.horizontal, 16)
                        .accessibilityIdentifier("jellyfin.offline")
                }
                switch page {
                case .overview: OverviewPage(overview: overview, spotlight: spotlight) { drawSpotlight() }
                case .films: grid(store.films)
                case .series: grid(store.series)
                case .libraries:
                    if let library { grid((store.films + store.series).filter { store.libraries(of: $0).contains(library.id) }) } else { libraries }
                }
            }
            .padding(.vertical, 8)
        }
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle("Jellyfin")
        .navigationDestination(for: DetailTarget.self) { DetailPage(target: $0) }
        .navigationDestination(for: JellyfinOverview.Tile.Kind.self) { kind in
            BrowseView(kind: kind, items: (overview.genres + overview.decades).first { $0.kind == kind }?.items ?? [])
        }
        .task { await store.loadLibrary(forceRefresh: false); await store.refreshHome() }
        .refreshable { await store.loadLibrary(forceRefresh: true); await store.refreshHome() }
        .task(id: overviewInputs) {
            overview = JellyfinOverview.build(films: store.films, series: store.series)
            if !overview.spotlightCandidates.contains(where: { $0.id == spotlight?.id }) { drawSpotlight() }
        }
    }

    static func title(_ page: Page) -> LocalizedStringKey {
        switch page {
        case .overview: "Overview"
        case .films: "Movies"
        case .series: "Series"
        case .libraries: "Libraries"
        }
    }

    private var overviewInputs: String {
        let store = model.jellyfin
        let all = store.films + store.series
        let played = all.filter(\.isPlayed).count, favorites = all.filter(\.isFavorite).count
        let left = store.series.reduce(0) { $0 + ($1.userData?.unplayedItemCount ?? 0) }
        return "\(store.films.count).\(store.series.count).\(played).\(favorites).\(left)"
    }

    private func drawSpotlight() {
        spotlight = JellyfinOverview.pick(from: overview.spotlightCandidates, avoiding: recentSpotlights)
        if let id = spotlight?.id { recentSpotlights = Array((recentSpotlights + [id]).suffix(5)) }
    }

    private func grid(_ items: [JFItem]) -> some View {
        JellyfinGrid(items: items)
    }

    private var libraries: some View {
        VStack(spacing: 8) {
            ForEach(model.jellyfin.libraries, id: \.id) { item in
                Button { library = item } label: {
                    HStack {
                        Text(verbatim: item.name)
                        Spacer()
                        Text(item.collectionType == "movies" ? "Movies" : "Series").foregroundStyle(TVTheme.tertiary)
                        Image(systemName: "chevron.right").foregroundStyle(TVTheme.tertiary)
                    }
                    .padding(14)
                    .background(TVTheme.tile, in: .rect(cornerRadius: 12))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Jellyfin items as a poster grid that fits the width.
private struct JellyfinGrid: View {
    @EnvironmentObject private var model: TVModel
    let items: [JFItem]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 12, alignment: .top)], alignment: .leading, spacing: 18) {
            ForEach(items, id: \.id) { item in
                NavigationLink(value: DetailTarget.jellyfin(item)) {
                    PosterCard(title: item.name, image: model.jellyfin.posterURL(item).flatMap(URL.init(string:)),
                               rating: item.communityRating,
                               progress: item.userData?.playedPercentage.flatMap { $0 > 0 ? $0 / 100 : nil },
                               watched: item.type == "Movie" && item.userData?.played == true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("jellyfin.item.\(item.id)")
            }
        }
        .padding(.horizontal, 16)
    }
}

/// A genre's or decade's titles.
private struct BrowseView: View {
    let kind: JellyfinOverview.Tile.Kind
    let items: [JFItem]

    var body: some View {
        ScrollView { JellyfinGrid(items: items).padding(.vertical, 12) }
            .background(TVTheme.background.ignoresSafeArea())
            .navigationTitle(OverviewPage.title(kind))
    }
}

/// Übersicht: a suggestion, Continue Watching, Recently Added, rows to discover the library and
/// tiles to browse it (FernsyCore `JellyfinOverview`).
private struct OverviewPage: View {
    @EnvironmentObject private var model: TVModel
    let overview: JellyfinOverview
    let spotlight: JFItem?
    let another: () -> Void

    var body: some View {
        let store = model.jellyfin
        LazyVStack(alignment: .leading, spacing: 24) {
            if let numbers {
                Text(verbatim: numbers).font(.subheadline).foregroundStyle(TVTheme.secondary).padding(.horizontal, 16)
                    .accessibilityIdentifier("jellyfin.numbers")
            }
            if let spotlight {
                Spotlight(item: spotlight, canDrawAgain: overview.spotlightCandidates.count > 1, another: another)
            }
            if !store.resume.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    RowTitle(title: "Continue Watching")
                    CardRow {
                        ForEach(store.resume, id: \.id) { item in
                            Button { model.play(.jellyfin(item)) } label: {
                                WideCard(title: item.seriesName ?? item.name, detail: VODItem.jellyfin(item).subtitle ?? "",
                                         image: store.thumbURL(item).flatMap(URL.init(string:)),
                                         progress: item.userData?.playedPercentage.map { $0 / 100 })
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("jellyfin.resume.\(item.id)")
                        }
                    }
                }
            }
            posterRow("Recently Added", note: "Movies and Series", id: "latest", store.latestFilms + store.latestSeries)
            posterRow("Your Favorites", note: nil, id: "favorites", overview.favorites)
            posterRow("Unwatched & Top Rated", note: nil, id: "top", overview.topRated)
            posterRow("Almost Finished", note: "Series", id: "almost", overview.almostDone)
            posterRow("Short & Good", note: "Under 100 minutes", id: "short", overview.shortAndGood)
            tileRow("Browse by Genre", overview.genres)
            tileRow("Browse by Decade", overview.decades)
            posterRow("Rediscover", note: "Watched over a year ago", id: "rediscover", overview.rediscover)
        }
    }

    private var numbers: String? {
        guard overview.filmCount + overview.seriesCount > 0 else { return nil }
        var parts = [String(localized: "\(overview.filmCount) movies"), String(localized: "\(overview.seriesCount) series")]
        if let hours = overview.unwatchedHours, hours > 0 { parts.append(String(localized: "\(hours) hrs unwatched")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func posterRow(_ title: LocalizedStringKey, note: LocalizedStringKey?, id: String, _ items: [JFItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                RowTitle(title: title, note: note)
                CardRow {
                    ForEach(items, id: \.id) { item in
                        NavigationLink(value: DetailTarget.jellyfin(item)) {
                            PosterCard(title: item.name, image: model.jellyfin.posterURL(item).flatMap(URL.init(string:)),
                                       rating: item.communityRating, watched: item.type == "Movie" && item.isPlayed)
                                .frame(width: 120)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("jellyfin.\(id).\(item.id)")
                    }
                }
            }
        }
    }

    @ViewBuilder private func tileRow(_ title: LocalizedStringKey, _ tiles: [JellyfinOverview.Tile]) -> some View {
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                RowTitle(title: title)
                CardRow {
                    ForEach(tiles) { tile in
                        NavigationLink(value: tile.kind) {
                            WideCard(title: Self.title(tile.kind), detail: String(localized: "\(tile.items.count) titles"),
                                     image: tile.artwork.flatMap { model.jellyfin.backdropURL($0) ?? model.jellyfin.thumbURL($0) }.flatMap(URL.init(string:)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("jellyfin.tile.\(tile.id)")
                    }
                }
            }
        }
    }

    static func title(_ kind: JellyfinOverview.Tile.Kind) -> String {
        switch kind {
        case .genre(let name): name
        case .decade(let year): String(localized: "\(String(year))s")
        }
    }
}

/// The suggestion: an unwatched, well-rated film with Play, Another Suggestion and Details.
private struct Spotlight: View {
    @EnvironmentObject private var model: TVModel
    let item: JFItem
    let canDrawAgain: Bool
    let another: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    private static let padHeight: CGFloat = 440

    var body: some View {
        // 16:9 on iPhone; on iPad a fixed height, since 16:9 of the iPad's width fills the
        // screen (as the Start hero). Title and buttons lie on the picture.
        Color.clear
            .aspectRatio(sizeClass == .regular ? nil : 16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(height: sizeClass == .regular ? Self.padHeight : nil)
            // Cropped near the top on iPad: faces sit in the upper part of a backdrop. A few
            // percent go at the top, as long as the picture still reaches the bottom.
            .overlay(alignment: .top) {
                RemoteImage(url: (model.jellyfin.backdropURL(item) ?? model.jellyfin.posterURL(item)).flatMap(URL.init(string:)), maxPixel: 1200) {
                    ArtPlaceholder(seed: item.name)
                }
                .alignmentGuide(.top) { d in sizeClass == .regular ? max(0, min(d.height * 0.06, d.height - Self.padHeight)) : d[.top] }
            }
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.8), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SUGGESTION").font(.caption.weight(.bold)).tracking(1.2).opacity(0.8)
                        Text(verbatim: item.name).font(.title2.bold()).lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        Button { model.play(.jellyfin(item)) } label: { Label("Play", systemImage: "play.fill") }
                            .buttonStyle(ActionButtonStyle())
                            .accessibilityIdentifier("jellyfin.spotlight.play")
                        if canDrawAgain {
                            Button(action: another) { Text("Another Suggestion") }
                                .buttonStyle(ActionButtonStyle(prominent: false))
                                .accessibilityIdentifier("jellyfin.spotlight.another")
                        }
                        NavigationLink(value: DetailTarget.jellyfin(item)) { Image(systemName: "info.circle") }
                            .buttonStyle(ActionButtonStyle(prominent: false))
                            .accessibilityIdentifier("jellyfin.spotlight.details")
                    }
                }
                .padding(14)
            }
            .clipShape(.rect(cornerRadius: 14))
            .padding(.horizontal, 16)
    }
}

// MARK: Search

/// Search (ios-app "Search"): the system search field and results while typing, live TV shows,
/// then films and series of both sources, with the Mac's matching rules.
struct SearchView: View {
    @EnvironmentObject private var model: TVModel
    @State private var query = ""
    @State private var index = SearchIndex(entries: [])
    @State private var asked: (show: EPGEntry, channel: LiveChannel)?

    var body: some View {
        ScrollView {
            results.padding(.vertical, 12)
        }
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Channels, shows, movies, series"))
        .navigationDestination(for: DetailTarget.self) { DetailPage(target: $0) }
        .task(id: model.movies.count + model.series.count + model.jellyfin.films.count + model.jellyfin.series.count) { await buildIndex() }
        .task { for channel in liveChannels { await model.loadGuide(for: channel) } }
        .sheet(isPresented: Binding(get: { asked != nil }, set: { if !$0 { asked = nil } })) {
            if let asked { ShowDetailSheet(show: asked.show, channel: asked.channel) }
        }
        #if DEBUG
        // IPTV_SEARCH=<query>: types it (screenshots without touch input).
        .onAppear { if let text = ProcessInfo.processInfo.environment["IPTV_SEARCH"], query.isEmpty { query = text } }
        #endif
    }

    /// The channels searched: favourites, recently watched, then the first visible ones (at most
    /// 50, like the Mac's programme search).
    private var liveChannels: [LiveChannel] {
        var seen = Set<Int>()
        return (model.channels(for: .favorites) + model.channels(for: .recent) + model.channels(for: .all))
            .filter { seen.insert($0.id).inserted }.prefix(50).map { $0 }
    }

    private var liveHits: [(show: EPGEntry, channel: LiveChannel)] {
        let needle = makeSearchKey(query)
        guard needle.count >= 2 else { return [] }
        let now = Date()
        var hits: [(show: EPGEntry, channel: LiveChannel)] = []
        for channel in liveChannels {
            for show in model.guide.guide(channel.id).entries ?? [] where show.end > now && makeSearchKey(show.title).contains(needle) {
                hits.append((show, channel))
            }
        }
        return Array(hits.sorted { ($0.show.start <= now ? 0 : 1, $0.show.start) < ($1.show.start <= now ? 0 : 1, $1.show.start) }.prefix(12))
    }

    private func buildIndex() async {
        let movies = model.movies.map(\.name), series = model.series.map(\.name)
        let films = model.jellyfin.films.map(\.name), shows = model.jellyfin.series.map(\.name)
        index = await Task.detached(priority: .utility) {
            var entries: [SearchEntry] = []
            for (i, name) in movies.enumerated() { entries.append(SearchEntry(source: .movies, index: i, key: makeSearchKey(name))) }
            for (i, name) in series.enumerated() { entries.append(SearchEntry(source: .series, index: i, key: makeSearchKey(name))) }
            for (i, name) in films.enumerated() { entries.append(SearchEntry(source: .jellyfinFilms, index: i, key: makeSearchKey(name))) }
            for (i, name) in shows.enumerated() { entries.append(SearchEntry(source: .jellyfinSeries, index: i, key: makeSearchKey(name))) }
            return SearchIndex(entries: entries)
        }.value
    }

    private struct VODHit: Identifiable {
        let id: String
        let title: String
        let source: String
        let image: URL?
        let target: DetailTarget
    }

    private var vodHits: [VODHit] {
        let found = index.search(makeSearchKey(query))
        var hits: [VODHit] = []
        for i in found[.movies] ?? [] where i < model.movies.count {
            let movie = model.movies[i]
            hits.append(VODHit(id: "m\(movie.id)", title: movie.name, source: "IPTV", image: movie.poster.flatMap(URL.init(string:)), target: .movie(movie)))
        }
        for i in found[.series] ?? [] where i < model.series.count {
            let show = model.series[i]
            hits.append(VODHit(id: "s\(show.id)", title: show.name, source: "IPTV", image: show.cover.flatMap(URL.init(string:)), target: .series(show)))
        }
        for i in (found[.jellyfinFilms] ?? []) where i < model.jellyfin.films.count {
            let item = model.jellyfin.films[i]
            hits.append(VODHit(id: "j\(item.id)", title: item.name, source: "Jellyfin", image: model.jellyfin.posterURL(item).flatMap(URL.init(string:)), target: .jellyfin(item)))
        }
        for i in (found[.jellyfinSeries] ?? []) where i < model.jellyfin.series.count {
            let item = model.jellyfin.series[i]
            hits.append(VODHit(id: "j\(item.id)", title: item.name, source: "Jellyfin", image: model.jellyfin.posterURL(item).flatMap(URL.init(string:)), target: .jellyfin(item)))
        }
        return Array(hits.prefix(30))
    }

    @ViewBuilder private var results: some View {
        let live = liveHits, vod = vodHits
        VStack(alignment: .leading, spacing: 24) {
            if !live.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    RowTitle(title: "Live TV", note: "on now and later")
                    VStack(spacing: 8) {
                        ForEach(live, id: \.show.id) { hit in
                            Button { select(hit) } label: { LiveHit(show: hit.show, channel: hit.channel) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("search.live.\(hit.channel.id).\(Int(hit.show.start.timeIntervalSince1970))")
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            if !vod.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    RowTitle(title: "Movies and Series")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 12, alignment: .top)], alignment: .leading, spacing: 18) {
                        ForEach(vod) { hit in
                            NavigationLink(value: hit.target) {
                                PosterCard(title: hit.title, image: hit.image, badge: hit.source,
                                           badgeColor: hit.source == "Jellyfin" ? Color(hex: 0x6C65F0) : Color(hex: 0x0F0E12, opacity: 0.65))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("search.vod.\(hit.id)")
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            if query.count >= 2 && live.isEmpty && vod.isEmpty {
                Text("Nothing found for “\(query)”.").foregroundStyle(TVTheme.secondary).padding(.horizontal, 16)
            }
        }
    }

    private func select(_ hit: (show: EPGEntry, channel: LiveChannel)) {
        if hit.show.start <= Date() {
            model.zapSource = .all
            Task { await model.zap(to: hit.channel) }
        } else {
            asked = hit
        }
    }
}

private struct LiveHit: View {
    let show: EPGEntry
    let channel: LiveChannel

    var body: some View {
        HStack(spacing: 12) {
            ChannelLogo(channel: channel).frame(width: 56, height: 35)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: show.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(verbatim: detail).font(.caption).foregroundStyle(TVTheme.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(TVTheme.tile, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
    }

    private var detail: String {
        if show.start <= Date() {
            let minutes = max(1, Int((show.end.timeIntervalSinceNow / 60).rounded()))
            return String(localized: "\(channel.displayName) · on now, \(minutes) min left")
        }
        return "\(channel.displayName) · \(show.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }
}
