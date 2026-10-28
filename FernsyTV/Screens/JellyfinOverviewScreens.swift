import FernsyCore
import FernsyPlayer
import SwiftUI

/// Übersicht of the Jellyfin tab (tvos-jellyfin-overview): a suggestion from the library,
/// Continue Watching and Recently Added, then rows to discover the library and tiles to browse
/// it. The rows come from `JellyfinOverview`, built once per library change by JellyfinScreen.
struct JellyfinOverviewPage: View {
    @EnvironmentObject private var model: TVModel
    let overview: JellyfinOverview
    let spotlight: JFItem?
    let another: () -> Void

    var body: some View {
        let store = model.jellyfin
        LazyVStack(alignment: .leading, spacing: 30) {
            if let numbers {
                Text(verbatim: numbers).font(.system(size: 22)).foregroundStyle(TVTheme.secondary)
                    .accessibilityIdentifier("jellyfin.numbers")
            }
            if let spotlight {
                JellyfinSpotlight(item: spotlight, canDrawAgain: overview.spotlightCandidates.count > 1, another: another)
            }
            if !store.resume.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    RowTitle(title: "Continue Watching")
                    CardRow {
                        ForEach(store.resume, id: \.id) { item in
                            Button { model.play(.jellyfin(item)) } label: {
                                WideCard(title: item.seriesName ?? item.name, detail: VODItem.jellyfin(item).subtitle ?? remaining(item),
                                         image: store.thumbURL(item).flatMap(URL.init(string:)),
                                         progress: item.userData?.playedPercentage.map { $0 / 100 }, width: 360)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("jellyfin.resume.\(item.id)")
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                RowTitle(title: "Recently Added", note: "Movies and Series")
                CardRow {
                    ForEach(store.latestFilms + store.latestSeries, id: \.id) { item in
                        poster(item, id: "jellyfin.item.\(item.id)")
                    }
                }
            }
            posterRow("Your Favorites", note: nil, id: "favorites", overview.favorites)
            posterRow("Unwatched & Top Rated", note: nil, id: "top", overview.topRated)
            posterRow("Almost Finished", note: "Series", id: "almost", overview.almostDone)
            posterRow("Short & Good", note: "Under 100 minutes", id: "short", overview.shortAndGood)
            tileRow("Browse by Genre", overview.genres)
            tileRow("Browse by Decade", overview.decades)
            posterRow("Rediscover", note: "Watched over a year ago", id: "rediscover", overview.rediscover)
        }
    }

    /// "239 movies · 69 series · 412 hrs unwatched".
    private var numbers: String? {
        guard overview.filmCount + overview.seriesCount > 0 else { return nil }
        var parts = [String(localized: "\(overview.filmCount) movies"), String(localized: "\(overview.seriesCount) series")]
        if let hours = overview.unwatchedHours, hours > 0 { parts.append(String(localized: "\(hours) hrs unwatched")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func posterRow(_ title: LocalizedStringKey, note: LocalizedStringKey?, id: String, _ items: [JFItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                RowTitle(title: title, note: note)
                CardRow {
                    ForEach(items, id: \.id) { item in poster(item, id: "jellyfin.\(id).\(item.id)") }
                }
            }
        }
    }

    private func poster(_ item: JFItem, id: String) -> some View {
        let store = model.jellyfin
        let left = item.isSeries ? JellyfinOverview.episodesLeft(item) : nil
        // Almost finished series say how many episodes are left instead of the count circle.
        let almost = left.map { JellyfinOverview.Rules.almostDoneLeft.contains($0) && (item.recursiveItemCount ?? 0) > $0 } ?? false
        return NavigationLink(value: DetailTarget.jellyfin(item)) {
            PosterCard(title: item.name, image: store.posterURL(item).flatMap(URL.init(string:)), rating: item.communityRating,
                       badge: almost ? String(localized: "\(left ?? 0) episodes left") : nil, badgeColor: Color(hex: 0x6C65F0),
                       count: almost ? nil : item.userData?.unplayedItemCount,
                       watched: item.type == "Movie" && item.isPlayed)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private func tileRow(_ title: LocalizedStringKey, _ tiles: [JellyfinOverview.Tile]) -> some View {
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                RowTitle(title: title)
                CardRow {
                    ForEach(tiles) { tile in
                        NavigationLink(value: tile.kind) {
                            WideCard(title: Self.title(tile.kind), detail: String(localized: "\(tile.items.count) titles"),
                                     image: tile.artwork.flatMap { model.jellyfin.backdropURL($0) ?? model.jellyfin.thumbURL($0) }.flatMap(URL.init(string:)),
                                     width: 360)
                        }
                        .buttonStyle(.borderless)
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

    private func remaining(_ item: JFItem) -> String {
        guard let ticks = item.runTimeTicks else { return "" }
        let left = Double(ticks - (item.userData?.playbackPositionTicks ?? 0)) / 10_000_000
        return String(localized: "\(max(1, Int((left / 60).rounded()))) min left")
    }
}

/// The suggestion at the top: an unwatched, well-rated film with its backdrop, which moves while
/// a button here has focus (tvos-living-hero); "Another Suggestion" draws the next one.
private struct JellyfinSpotlight: View {
    @EnvironmentObject private var model: TVModel
    let item: JFItem
    let canDrawAgain: Bool
    let another: () -> Void
    @FocusState private var focus: Int?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.frame(height: 560)
                .overlay {
                    LivingBackdrop(urls: backdrops, active: focus != nil, seed: item.name)
                        .accessibilityElement()
                        .accessibilityIdentifier("jellyfin.spotlight.backdrop")
                        .accessibilityValue(focus != nil ? "moving" : "resting")
                }
                .clipped()
            LinearGradient(stops: [.init(color: TVTheme.background.opacity(0.92), location: 0), .init(color: TVTheme.background.opacity(0.45), location: 0.5),
                                   .init(color: .clear, location: 0.85)], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 16) {
                // Another suggestion's text eases in; the buttons keep their identity so focus stays.
                VStack(alignment: .leading, spacing: 16) {
                    Text("FROM YOUR LIBRARY").font(.system(size: 20, weight: .bold)).tracking(1.6).foregroundStyle(TVTheme.text.opacity(0.75))
                    Text(verbatim: item.name).font(.system(size: 64, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                    if !facts.isEmpty {
                        Text(verbatim: facts).font(.system(size: 24)).foregroundStyle(TVTheme.text.opacity(0.8))
                    }
                }
                .id(item.id)
                .transition(.opacity.combined(with: .offset(y: 12)))
                HStack(spacing: 20) {
                    Button { model.play(.jellyfin(item)) } label: { Label("Play", systemImage: "play.fill") }
                        .buttonStyle(ActionButtonStyle())
                        .focused($focus, equals: 0)
                        .accessibilityIdentifier("jellyfin.spotlight.play")
                    if canDrawAgain {
                        Button(action: another) { Label("Another Suggestion", systemImage: "shuffle") }
                            .buttonStyle(ActionButtonStyle())
                            .focused($focus, equals: 1)
                            .accessibilityIdentifier("jellyfin.spotlight.another")
                    }
                    NavigationLink(value: DetailTarget.jellyfin(item)) { Image(systemName: "info.circle") }
                        .buttonStyle(ActionButtonStyle(round: true))
                        .focused($focus, equals: 2)
                        .accessibilityIdentifier("jellyfin.spotlight.info")
                }
                .padding(.top, 10)
            }
            .animation(.easeOut(duration: 0.5), value: item.id)
            .frame(maxWidth: 1000, alignment: .leading)
            .padding(50)
        }
        .clipShape(.rect(cornerRadius: 24))
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("jellyfin.spotlight")
        .accessibilityValue(item.id)
    }

    /// All of the film's backdrops; without one the poster, else the placeholder.
    private var backdrops: [URL] {
        let list = model.jellyfin.backdropURLs(item)
        return (list.isEmpty ? model.jellyfin.posterURL(item, height: 1080).map { [$0] } ?? [] : list).compactMap(URL.init(string:))
    }

    /// "2019 · Comedy · 1 hr 38 min · ★ 7.9", as far as known.
    private var facts: String {
        var list: [String] = []
        if let year = item.productionYear { list.append("\(year)") }
        if let genre = item.genres?.first { list.append(genre) }
        if let ticks = item.runTimeTicks { list.append(Runtime.text(seconds: Double(ticks) / 10_000_000)) }
        if let rating = item.communityRating { list.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
        return list.joined(separator: " · ")
    }
}

/// A genre's or decade's titles as a poster grid, sorted by rating, name or year.
struct JellyfinBrowseScreen: View {
    enum Sort: CaseIterable { case rating, name, year }

    @EnvironmentObject private var model: TVModel
    let kind: JellyfinOverview.Tile.Kind
    let items: [JFItem]
    @State private var sort: Sort = .rating

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 20) {
                    Text(verbatim: JellyfinOverviewPage.title(kind)).font(.system(size: 44, weight: .bold))
                    Text("\(items.count) titles").font(.system(size: 22)).foregroundStyle(TVTheme.secondary)
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(Sort.allCases, id: \.self) { value in
                            Button { sort = value } label: {
                                Text(Self.title(value)).font(.system(size: 22, weight: .semibold)).padding(.horizontal, 22).frame(height: 46)
                            }
                            .buttonStyle(TabPillStyle(selected: sort == value))
                            .accessibilityIdentifier("browse.sort.\(value)")
                        }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.08), in: .capsule)
                }
                .focusSection()
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(200), spacing: 56), count: 7), alignment: .leading, spacing: 44) {
                    ForEach(sorted, id: \.id) { item in
                        NavigationLink(value: DetailTarget.jellyfin(item)) {
                            PosterCard(title: item.name, image: model.jellyfin.posterURL(item).flatMap(URL.init(string:)),
                                       rating: item.communityRating, count: item.userData?.unplayedItemCount,
                                       watched: item.type == "Movie" && item.isPlayed)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("browse.item.\(item.id)")
                    }
                }
                .padding(.vertical, 20)
                .focusSection()
            }
            .padding(.top, 10)
        }
        .contentMargins(.horizontal, 90, for: .scrollContent)
        .scrollClipDisabled()
        .background(TVTheme.background.ignoresSafeArea())
        .foregroundStyle(TVTheme.text)
        .toolbar(.hidden, for: .tabBar)
    }

    private var sorted: [JFItem] {
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
