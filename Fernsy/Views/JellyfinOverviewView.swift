import FernsyCore
import SwiftUI

/// Jellyfin's Übersicht on the Mac (mac-start-pages design 6): the rows of the Apple TV's
/// Übersicht from the same rules (FernsyCore `JellyfinOverview`), built once per library change.
struct JellyfinOverviewView: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    @EnvironmentObject private var app: AppModel
    @State private var overview = JellyfinOverview()
    @State private var spotlight: JFItem?
    /// The last suggestions, so "Another Suggestion" does not repeat them at once.
    @State private var recentSpotlights: [String] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Text(verbatim: jellyfin.session?.serverName ?? "Jellyfin").font(.title2.weight(.bold))
                    Circle().fill(jellyfin.isOffline ? Theme.warning : Theme.online).frame(width: 8, height: 8)
                    Text(jellyfin.isOffline ? "Offline" : "Connected").font(.callout).foregroundStyle(.secondary)
                    if let numbers { Text(verbatim: "· \(numbers)").font(.callout).foregroundStyle(.secondary) }
                }
                if let spotlight {
                    JellyfinSpotlightBanner(item: spotlight, canDrawAgain: overview.spotlightCandidates.count > 1) { drawSpotlight() }
                }
                if !jellyfin.resume.isEmpty {
                    PagingCarousel(title: Text("Continue Watching"), items: jellyfin.resume, itemWidth: 280, height: 210) { item in
                        Button { app.play(jellyfin: item) } label: { JellyfinWideCard(item: item) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                JellyfinItemMenu(item: item)
                                if let series = jellyfin.seriesItem(for: item), item.type == "Episode" {
                                    NavigationLink("Open Series", value: series)
                                }
                            }
                    }
                }
                posterRow(Text("Recently Added"), note: Text("Movies and Series"), jellyfin.latestFilms + jellyfin.latestSeries)
                posterRow(Text("Your Favorites"), overview.favorites)
                posterRow(Text("Unwatched & Top Rated"), overview.topRated)
                posterRow(Text("Almost Finished"), note: Text("Series"), overview.almostDone)
                posterRow(Text("Short & Good"), note: Text("Under 100 minutes"), overview.shortAndGood)
                tileRow(Text("Browse by Genre"), overview.genres)
                tileRow(Text("Browse by Decade"), overview.decades)
                posterRow(Text("Rediscover"), note: Text("Watched over a year ago"), overview.rediscover)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .safeAreaInset(edge: .top, spacing: 0) { JellyfinStatusBanner() }
        .overlay {
            if jellyfin.films.isEmpty && jellyfin.series.isEmpty && jellyfin.resume.isEmpty {
                if jellyfin.isLoading { ProgressView() } else { ContentUnavailableView("Nothing to Watch Yet", systemImage: "square.grid.2x2") }
            }
        }
        .navigationTitle(LibrarySection.jellyfinHome.title)
        .task { await jellyfin.refreshHome() }
        .task(id: overviewInputs) {
            overview = JellyfinOverview.build(films: jellyfin.films, series: jellyfin.series)
            if !overview.spotlightCandidates.contains(where: { $0.id == spotlight?.id }) { drawSpotlight() }
        }
    }

    /// What the rows read: the lists and the watched and favourite marks.
    private var overviewInputs: String {
        let all = jellyfin.films + jellyfin.series
        let played = all.filter(\.isPlayed).count, favorites = all.filter(\.isFavorite).count
        let left = jellyfin.series.reduce(0) { $0 + ($1.userData?.unplayedItemCount ?? 0) }
        return "\(jellyfin.films.count).\(jellyfin.series.count).\(played).\(favorites).\(left)"
    }

    private func drawSpotlight() {
        spotlight = JellyfinOverview.pick(from: overview.spotlightCandidates, avoiding: recentSpotlights)
        if let id = spotlight?.id { recentSpotlights = Array((recentSpotlights + [id]).suffix(5)) }
    }

    /// "239 movies · 69 series · 412 hrs unwatched".
    private var numbers: String? {
        guard overview.filmCount + overview.seriesCount > 0 else { return nil }
        var parts = [String(localized: "\(overview.filmCount) movies"), String(localized: "\(overview.seriesCount) series")]
        if let hours = overview.unwatchedHours, hours > 0 { parts.append(String(localized: "\(hours) hrs unwatched")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func posterRow(_ title: Text, note: Text? = nil, _ items: [JFItem]) -> some View {
        if !items.isEmpty {
            PagingCarousel(title: title, note: note, items: items, itemWidth: 160, height: 320) { item in
                NavigationLink(value: item) {
                    JellyfinPoster(item: item).frame(width: 160).fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .contextMenu { JellyfinItemMenu(item: item) }
            }
        }
    }

    @ViewBuilder private func tileRow(_ title: Text, _ tiles: [JellyfinOverview.Tile]) -> some View {
        if !tiles.isEmpty {
            PagingCarousel(title: title, items: tiles, itemWidth: 280, height: 190) { tile in
                NavigationLink(value: tile.kind) { JellyfinTileCard(tile: tile) }
                    .buttonStyle(.plain)
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

/// The suggestion: an unwatched, well-rated film over its backdrop, which moves while the
/// pointer is over it; "Another Suggestion" draws the next one.
private struct JellyfinSpotlightBanner: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    @EnvironmentObject private var app: AppModel
    let item: JFItem
    let canDrawAgain: Bool
    let another: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LivingBackdrop(urls: backdrops, active: hovering)
                // As tall as fits: in a small window the title and buttons stay in view.
                .containerRelativeFrame(.vertical) { height, _ in min(360, max(240, height * 0.62)) }
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(stops: [.init(color: .black.opacity(0.85), location: 0), .init(color: .black.opacity(0.35), location: 0.5),
                                   .init(color: .clear, location: 0.85)], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 10) {
                Text("FROM YOUR LIBRARY").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.white.opacity(0.75))
                Text(verbatim: item.name).font(.system(size: 36, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                if !facts.isEmpty { Text(verbatim: facts).font(.title3).foregroundStyle(.white.opacity(0.8)) }
                HStack(spacing: 12) {
                    Button { app.play(jellyfin: item) } label: { Label("Play", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                    if canDrawAgain {
                        Button(action: another) { Label("Another Suggestion", systemImage: "shuffle") }
                    }
                    NavigationLink("Details", value: item)
                }
                .controlSize(.large)
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 640, alignment: .leading)
            .padding(28)
            .id(item.id)
            .transition(.opacity.combined(with: .offset(y: 8)))
        }
        .animation(.easeOut(duration: 0.4), value: item.id)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onHover { hovering = $0 }
    }

    /// All of the film's backdrops; without one the poster.
    private var backdrops: [URL] {
        let list = jellyfin.backdropURLs(item)
        return (list.isEmpty ? jellyfin.posterURL(item, height: 1080).map { [$0] } ?? [] : list).compactMap(URL.init(string:))
    }

    /// "2019 · Comedy · ★ 7.9", as far as known.
    private var facts: String {
        var list: [String] = []
        if let year = item.productionYear { list.append("\(year)") }
        if let genre = item.genres?.first { list.append(genre) }
        if let rating = item.communityRating { list.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
        return list.joined(separator: " · ")
    }
}

/// Continue Watching: still, title, episode and progress.
private struct JellyfinWideCard: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    let item: JFItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .frame(width: 280, height: 158)
                .overlay { RemoteImage(url: jellyfin.thumbURL(item), maxPixel: 600) { Rectangle().fill(.quaternary) } }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottom) {
                    if let progress = item.progress { ProgressBar(value: progress, height: 4).padding(10) }
                }
            Text(verbatim: item.seriesName ?? item.name).font(.callout.weight(.medium)).lineLimit(1)
            if let line = StartBuilder.episodeLine(item) {
                Text(verbatim: line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 280, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A genre or decade tile: the best rated title's artwork with the name and count.
private struct JellyfinTileCard: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    let tile: JellyfinOverview.Tile
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(width: 280, height: 158)
                .overlay {
                    RemoteImage(url: tile.artwork.flatMap { jellyfin.backdropURL($0) ?? jellyfin.thumbURL($0) }, maxPixel: 600) {
                        Rectangle().fill(.quaternary)
                    }
                }
            LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .bottom, endPoint: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: JellyfinOverviewView.title(tile.kind)).font(.title3.weight(.bold))
                Text("\(tile.items.count) titles").font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)
            .padding(12)
        }
        .frame(width: 280, height: 158)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.snappy(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// A genre's or decade's titles as a poster grid, sorted by rating, name or year.
struct JellyfinBrowseView: View {
    enum Sort: CaseIterable { case rating, name, year }

    @EnvironmentObject private var jellyfin: JellyfinStore
    let kind: JellyfinOverview.Tile.Kind
    @State private var sort: Sort = .rating
    /// The tile's titles, found once per library change (not on every redraw).
    @State private var items: [JFItem] = []

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 20)], alignment: .leading, spacing: 24) {
                ForEach(sorted(items)) { item in
                    NavigationLink(value: item) { JellyfinPoster(item: item) }
                        .buttonStyle(.plain)
                        .contextMenu { JellyfinItemMenu(item: item) }
                }
            }
            .padding(24)
        }
        .navigationTitle(JellyfinOverviewView.title(kind))
        .navigationSubtitle(Text("\(items.count) titles"))
        .task(id: "\(jellyfin.films.count).\(jellyfin.series.count)") {
            let overview = JellyfinOverview.build(films: jellyfin.films, series: jellyfin.series)
            items = (overview.genres + overview.decades).first { $0.kind == kind }?.items ?? []
        }
        .toolbar {
            ToolbarItem {
                Picker("Sort", selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { value in Text(Self.title(value)).tag(value) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func sorted(_ items: [JFItem]) -> [JFItem] {
        switch sort {
        case .rating: items.sorted { ($0.communityRating ?? 0) > ($1.communityRating ?? 0) }
        case .name: items.sorted { ($0.sortName ?? $0.name).localizedStandardCompare($1.sortName ?? $1.name) == .orderedAscending }
        case .year: items.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        }
    }

    static func title(_ sort: Sort) -> LocalizedStringKey {
        switch sort {
        case .rating: "Rating"
        case .name: "A–Z"
        case .year: "Year"
        }
    }
}
