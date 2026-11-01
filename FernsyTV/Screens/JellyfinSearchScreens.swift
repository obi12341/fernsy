import FernsyCore
import FernsyPlayer
import SwiftUI

/// Jellyfin (design screen `jellyfin`): the server's state and the views Overview, Films, Series
/// and Libraries.
struct JellyfinScreen: View {
    enum Page: CaseIterable { case overview, films, series, libraries }

    @EnvironmentObject private var model: TVModel
    @State private var view: Page = .overview
    @State private var library: JFItem?
    /// Übersicht's rows and suggestion, built once per library change (tvos-jellyfin-overview).
    @State private var overview = JellyfinOverview()
    @State private var spotlight: JFItem?
    @State private var recentSpotlights: [String] = []

    var body: some View {
        NavigationStack {
            let store = model.jellyfin
            // The header scrolls with the content, as on the IPTV grids: nothing slides over the
            // view switcher, and the scroll view spans the screen so posters are dropped off-screen
            // (tvos-edge-scrolling).
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 20) {
                        Text("Jellyfin").font(.system(size: 44, weight: .bold))
                        HStack(spacing: 8) {
                            Circle().fill(store.isOffline ? TVTheme.warning : Color(hex: 0x4CD07D)).frame(width: 10, height: 10)
                            Text(verbatim: "\(store.session?.serverName ?? "") · \(store.isOffline ? String(localized: "not reachable") : String(localized: "connected"))")
                        }
                        .font(.system(size: 21)).foregroundStyle(TVTheme.text.opacity(0.65))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("jellyfin.state")
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach(Page.allCases, id: \.self) { value in
                                Button { view = value; library = nil } label: {
                                    Text(Self.title(value)).font(.system(size: 22, weight: .semibold)).padding(.horizontal, 22).frame(height: 46)
                                }
                                .buttonStyle(TabPillStyle(selected: view == value))
                                .accessibilityIdentifier("jellyfin.view.\(value)")
                            }
                        }
                        .padding(6)
                        .background(Color.white.opacity(0.08), in: .capsule)
                    }
                    // Header and content as focus sections: otherwise Up from the content skips the
                    // views and goes to the tab bar (as in the film grid).
                    .focusSection()
                    if store.isOffline {
                        Text("The server cannot be reached. Showing what was loaded last.")
                            .font(.system(size: 22)).foregroundStyle(TVTheme.warning)
                            .accessibilityIdentifier("jellyfin.offline")
                    }
                    VStack(alignment: .leading, spacing: 30) {
                        switch view {
                        case .overview: JellyfinOverviewPage(overview: overview, spotlight: spotlight) { drawSpotlight() }
                        case .films: grid(store.films)
                        case .series: grid(store.series)
                        case .libraries:
                            if let library { grid((store.films + store.series).filter { store.libraries(of: $0).contains(library.id) }) } else { libraries }
                        }
                    }
                    .padding(.vertical, 10)
                    .focusSection()
                }
                .padding(.top, 10)
            }
            .contentMargins(.horizontal, 90, for: .scrollContent)
            .scrollClipDisabled()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TVTheme.background.ignoresSafeArea())
            .foregroundStyle(TVTheme.text)
            .navigationDestination(for: DetailTarget.self) { DetailScreen(target: $0) }
            .navigationDestination(for: JellyfinOverview.Tile.Kind.self) { kind in
                JellyfinBrowseScreen(kind: kind, items: (overview.genres + overview.decades).first { $0.kind == kind }?.items ?? [])
            }
            .task { await store.loadLibrary(forceRefresh: false); await store.refreshHome() }
            .task(id: overviewInputs) {
                overview = JellyfinOverview.build(films: store.films, series: store.series)
                // The suggestion stays while it is still a candidate (not watched meanwhile).
                if !overview.spotlightCandidates.contains(where: { $0.id == spotlight?.id }) { drawSpotlight() }
            }
        }
    }

    static func title(_ view: Page) -> LocalizedStringKey {
        switch view {
        case .overview: "Overview"
        case .films: "Movies"
        case .series: "Series"
        case .libraries: "Libraries"
        }
    }

    /// What Übersicht's rows read: the lists and the watched and favourite marks.
    private var overviewInputs: String { model.jellyfinOverviewInputs }

    private func drawSpotlight() {
        spotlight = JellyfinOverview.pick(from: overview.spotlightCandidates, avoiding: recentSpotlights)
        if let id = spotlight?.id { recentSpotlights = Array((recentSpotlights + [id]).suffix(5)) }
    }

    private func grid(_ items: [JFItem]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(200), spacing: 56), count: 7), alignment: .leading, spacing: 44) {
            ForEach(items, id: \.id) { item in
                NavigationLink(value: DetailTarget.jellyfin(item)) {
                    PosterCard(title: item.name, image: model.jellyfin.posterURL(item).flatMap(URL.init(string:)),
                               rating: item.communityRating, count: item.userData?.unplayedItemCount,
                               progress: item.userData?.playedPercentage.flatMap { $0 > 0 ? $0 / 100 : nil },
                               watched: item.type == "Movie" && item.userData?.played == true)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("jellyfin.item.\(item.id)")
            }
        }
        .padding(.vertical, 20)
    }

    private var libraries: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.jellyfin.libraries, id: \.id) { item in
                Button { library = item } label: {
                    SettingsRow(title: Text(verbatim: item.name), value: Text(item.collectionType == "movies" ? "Movies" : "Series"))
                }
                .buttonStyle(TVTileStyle(rest: .white.opacity(0.06), radius: 16, scale: 1.03))
            }
        }
        .frame(maxWidth: 1100)
    }
}

struct TabPillStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, selected: selected)
    }

    private struct Pill: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundStyle(focused ? TVTheme.focusedText : selected ? TVTheme.text : TVTheme.text.opacity(0.65))
                .background(focused ? TVTheme.focused : selected ? Color.white.opacity(0.18) : .clear, in: .capsule)
                .scaleEffect(focused ? 1.05 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// Search (design screen `suche`, design D): a letter row, dictation and iPhone typing through
/// the system field, and results while typing: live TV shows, then films and series.
struct SearchScreen: View {
    @EnvironmentObject private var model: TVModel
    @State private var query = ""
    @State private var index = SearchIndex(entries: [])
    @State private var asked: (show: EPGEntry, channel: LiveChannel)?

    static let keys = Array("abcdefghijklmnopqrstuvwxyzäöü").map(String.init) + [" ", "⌫"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    HStack(spacing: 4) {
                        Text(verbatim: query).font(.system(size: 44, weight: .semibold))
                        Rectangle().fill(TVTheme.text).frame(width: 3, height: 44)
                    }
                    .frame(minWidth: 200, minHeight: 56)
                    .accessibilityElement()
                    .accessibilityIdentifier("search.query")
                    .accessibilityValue(query)
                    HStack(spacing: 6) {
                        ForEach(Self.keys, id: \.self) { key in
                            Button { type(key) } label: {
                                Group {
                                    if key == " " { Image(systemName: "space") } else if key == "⌫" { Image(systemName: "delete.left") } else { Text(verbatim: key) }
                                }
                                .font(.system(size: 26, weight: .medium)).frame(width: 50, height: 56)
                            }
                            .buttonStyle(TVTileStyle(rest: .clear, radius: 12, scale: 1.1))
                            .accessibilityIdentifier("key.\(key == " " ? "space" : key == "⌫" ? "delete" : key)")
                        }
                    }
                    .focusSection()
                    // The query shows above; this line opens tvOS' text entry for it.
                    TVTextEntry(text: $query, prompt: String(localized: "Search")) {
                        Text("Dictate with the Siri button or type on your iPhone")
                            .font(.system(size: 19))
                            .opacity(0.55)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(TVTileStyle(rest: .clear, radius: 12))
                    .accessibilityIdentifier("search.field")
                    // As wide as the letter row: Down from any key reaches it.
                    .frame(maxWidth: .infinity)
                    .focusSection()
                    // A focus section: Down from the centred search line reaches the first hit on the left.
                    results.frame(maxWidth: .infinity, alignment: .leading).focusSection().padding(.top, 30)
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 20)
            }
            .background(TVTheme.background.ignoresSafeArea())
            .foregroundStyle(TVTheme.text)
            .navigationDestination(for: DetailTarget.self) { DetailScreen(target: $0) }
            .task(id: model.movies.count + model.series.count + model.jellyfin.films.count + model.jellyfin.series.count) { await buildIndex() }
            .task { for channel in liveChannels { await model.loadGuide(for: channel) } }
            .confirmationDialog(asked.map { $0.show.title } ?? "", isPresented: Binding(get: { asked != nil }, set: { if !$0 { asked = nil } }),
                                presenting: asked) { item in
                Button("Record") { model.notice = model.schedule(item.show, on: item.channel) }
            } message: { item in
                Text("\(item.channel.displayName) · \(TimeSpan.of(item.show)). Records only while Fernsy is open.")
            }
        }
    }

    private func type(_ key: String) {
        if key == "⌫" { if !query.isEmpty { query.removeLast() } } else { query += key }
    }

    // MARK: Live TV

    /// The channels searched: favourites, recently watched, then the first visible ones (at
    /// most 50, like the Mac's programme search).
    private var liveChannels: [LiveChannel] { model.searchChannels }

    private var liveHits: [(show: EPGEntry, channel: LiveChannel)] { model.liveSearchHits(query) }

    // MARK: Films and series

    private func buildIndex() async { index = await model.searchIndex() }

    private var vodHits: [VODHit] { model.vodSearchHits(query, in: index) }

    @ViewBuilder private var results: some View {
        let live = liveHits, vod = vodHits
        VStack(alignment: .leading, spacing: 40) {
            if !live.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    RowTitle(title: "Live TV", note: "on now and later")
                    CardRow {
                        ForEach(live, id: \.show.id) { hit in
                            Button { select(hit) } label: { LiveHit(show: hit.show, channel: hit.channel) }
                                .buttonStyle(TVTileStyle(radius: 20, scale: 1.05))
                                .accessibilityIdentifier("search.live.\(hit.channel.id).\(Int(hit.show.start.timeIntervalSince1970))")
                        }
                    }
                }
            }
            if !vod.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    RowTitle(title: "Movies and Series")
                    CardRow {
                        ForEach(vod) { hit in
                            NavigationLink(value: hit.target) {
                                PosterCard(title: hit.title, image: hit.image, badge: hit.source,
                                           badgeColor: hit.source == "Jellyfin" ? Color(hex: 0x6C65F0) : Color(hex: 0x0F0E12, opacity: 0.65), width: 180)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("search.vod.\(hit.id)")
                        }
                    }
                }
            }
            if query.count >= 2 && live.isEmpty && vod.isEmpty {
                Text("Nothing found for “\(query)”.").font(.system(size: 26)).foregroundStyle(TVTheme.secondary)
            }
        }
    }

    private func select(_ hit: (show: EPGEntry, channel: LiveChannel)) {
        if hit.show.start <= Date() {
            model.zapSource = .all
            model.play(hit.channel)
        } else {
            asked = hit
        }
    }
}

private struct LiveHit: View {
    let show: EPGEntry
    let channel: LiveChannel

    var body: some View {
        HStack(spacing: 16) {
            ChannelLogo(channel: channel, radius: 11).frame(width: 104, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: show.title).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                Text(verbatim: detail).font(.system(size: 19)).opacity(0.6).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 420, alignment: .leading)
    }

    private var detail: String { LibraryText.liveHit(show, on: channel) }
}
