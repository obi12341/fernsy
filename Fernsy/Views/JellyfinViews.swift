import SwiftUI

// MARK: - Library helpers

enum JFKind {
    case films, series

    var itemType: String { self == .films ? "Movie" : "Series" }
    var collectionType: String { self == .films ? "movies" : "tvshows" }
}

enum JFSort: String, CaseIterable, Identifiable {
    case added, name, release, rating
    var id: String { rawValue }
    var title: String {
        switch self {
        case .added: return String(localized: "Zuletzt hinzugefügt")
        case .name: return String(localized: "Name")
        case .release: return String(localized: "Erscheinungsdatum")
        case .rating: return String(localized: "Bewertung")
        }
    }
}

/// Category ids in the category column: "favorites", "lib:<id>", "genre:<name>".
extension JellyfinStore {
    func items(_ kind: JFKind) -> [JFItem] { kind == .films ? films : series }

    struct CategoryRow {
        let id: String
        let name: String
        let count: Int
    }

    func categoryRows(_ kind: JFKind) -> [CategoryRow] {
        let all = items(kind)
        var rows = [CategoryRow(id: "favorites", name: String(localized: "Favoriten"), count: all.filter(\.isFavorite).count)]
        for lib in libraries where lib.collectionType == kind.collectionType {
            rows.append(CategoryRow(id: "lib:\(lib.id)", name: lib.name, count: all.filter { libraries(of: $0).contains(lib.id) }.count))
        }
        var genres: [String: Int] = [:]
        for item in all { for genre in item.genres ?? [] { genres[genre, default: 0] += 1 } }
        for (genre, count) in genres.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
            rows.append(CategoryRow(id: "genre:\(genre)", name: genre, count: count))
        }
        return rows
    }

    func filtered(_ kind: JFKind, categoryID: String, query: String, sort: JFSort) -> [JFItem] {
        var list = items(kind)
        if categoryID == "favorites" {
            list = list.filter(\.isFavorite)
        } else if categoryID.hasPrefix("lib:") {
            let lib = String(categoryID.dropFirst(4))
            list = list.filter { libraries(of: $0).contains(lib) }
        } else if categoryID.hasPrefix("genre:") {
            let genre = String(categoryID.dropFirst(6))
            list = list.filter { $0.genres?.contains(genre) == true }
        }
        let needle = makeSearchKey(query)
        if !needle.isEmpty { list = list.filter { makeSearchKey($0.name).contains(needle) } }
        switch sort {
        case .added: list.sort { $0.addedKey > $1.addedKey }
        case .name: break // already by sort name
        case .release: list.sort { $0.releaseKey > $1.releaseKey }
        case .rating: list.sort { ($0.communityRating ?? 0) > ($1.communityRating ?? 0) }
        }
        return list
    }

    func seriesItem(for item: JFItem) -> JFItem? {
        if item.isSeries { return item }
        guard let id = item.seriesId else { return nil }
        return series.first { $0.id == id }
    }
}

private let posterColumns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20, alignment: .top)]

// MARK: - Status

/// Offline, expired session and failed writes, above every Jellyfin view.
struct JellyfinStatusBanner: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    @State private var signingIn = false

    var body: some View {
        VStack(spacing: 0) {
            if jellyfin.isExpired {
                banner(Text("Die Jellyfin-Sitzung ist abgelaufen."), systemImage: "person.crop.circle.badge.exclamationmark") {
                    Button("Neu anmelden") { signingIn = true }
                }
            } else if jellyfin.isOffline {
                banner(Text("Der Jellyfin-Server ist nicht erreichbar – gespeicherte Bibliothek."), systemImage: "wifi.slash") {
                    Button("Erneut versuchen") { Task { await jellyfin.loadLibrary(forceRefresh: true) } }
                }
            }
            if let error = jellyfin.lastError {
                banner(Text(verbatim: error), systemImage: "exclamationmark.triangle") {
                    Button("OK") { jellyfin.lastError = nil }
                }
            }
        }
        .sheet(isPresented: $signingIn) {
            JellyfinSignInForm(prefillServer: jellyfin.session?.server, prefillUser: jellyfin.session?.userName) { signingIn = false }
                .padding(24)
        }
    }

    private func banner(_ text: Text, systemImage: String, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
            text.lineLimit(2)
            Spacer()
            action()
        }
        .font(.callout)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.yellow.opacity(0.18))
    }
}

/// Play / Resume (at the server's position) and From the Beginning.
struct JellyfinPlayButton: View {
    @EnvironmentObject private var app: AppModel
    let item: JFItem

    var body: some View {
        let resume = item.isSeries ? 0 : Double(item.userData?.playbackPositionTicks ?? 0) / 10_000_000
        Button {
            app.play(jellyfin: item)
        } label: {
            Label(resume > 0 ? "Fortsetzen (\(formatTime(resume)))" : "Abspielen", systemImage: "play.fill")
                .padding(.horizontal, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        if resume > 0 {
            Button("Von vorne") { app.play(jellyfin: item, resume: false) }
                .controlSize(.large)
        }
    }
}

struct JellyfinItemMenu: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    @EnvironmentObject private var app: AppModel
    let item: JFItem

    var body: some View {
        if item.type != "Season" {
            Button("Abspielen") { app.play(jellyfin: item) }
            Divider()
        }
        Button(item.isPlayed ? "Als ungesehen markieren" : "Als gesehen markieren") {
            Task { await jellyfin.setPlayed(item, !item.isPlayed) }
        }
        if item.type == "Movie" || item.isSeries {
            Button(item.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") {
                Task { await jellyfin.setFavorite(item, !item.isFavorite) }
            }
        }
    }
}

// MARK: - Grid

struct JellyfinGridView: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    let kind: JFKind
    let categoryID: String
    let query: String
    @AppStorage("jellyfin.sort.films") private var filmSort: JFSort = .added
    @AppStorage("jellyfin.sort.series") private var seriesSort: JFSort = .added

    private var sort: Binding<JFSort> { kind == .films ? $filmSort : $seriesSort }

    var body: some View {
        let list = jellyfin.filtered(kind, categoryID: categoryID, query: query, sort: sort.wrappedValue)
        ScrollView {
            LazyVGrid(columns: posterColumns, spacing: 24) {
                ForEach(list) { item in
                    NavigationLink(value: item) {
                        JellyfinPoster(item: item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { JellyfinItemMenu(item: item) }
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .top, spacing: 0) { JellyfinStatusBanner() }
        .overlay {
            if list.isEmpty && !jellyfin.items(kind).isEmpty {
                ContentUnavailableView.search(text: query)
            } else if jellyfin.items(kind).isEmpty && jellyfin.isLoading {
                ProgressView("Bibliothek wird geladen …")
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Sortierung", selection: sort) {
                    ForEach(JFSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .help("Sortierung")
            }
        }
        .navigationTitle(kind == .films ? "Filme" : "Serien")
        .navigationSubtitle(kind == .films ? "\(list.count) Filme" : "\(list.count) Serien")
        .task(id: kind == .films) { await jellyfin.refreshUserData() }
    }
}

struct JellyfinPoster: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    let item: JFItem

    var body: some View {
        PosterCard(title: item.name, imageURL: jellyfin.posterURL(item), rating: item.communityRating,
                   isFavorite: item.isFavorite, subtitle: item.year.map(String.init),
                   watched: item.isPlayed, fraction: item.progress,
                   unwatchedCount: item.isSeries ? item.userData?.unplayedItemCount : nil)
    }
}

// MARK: - Detail

struct JellyfinItemDetailView: View {
    let item: JFItem

    var body: some View {
        if item.isSeries {
            JellyfinSeriesDetailView(seriesId: item.id, fallback: item)
        } else {
            JellyfinFilmDetailView(itemId: item.id, fallback: item)
        }
    }
}

/// Backdrop, poster, title and a slot for the content below.
private struct JellyfinDetailHeader<Content: View>: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    let item: JFItem
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(url: jellyfin.backdropURL(item, height: 1080), maxPixel: 1600) {
                Rectangle().fill(.quaternary)
            }
            .frame(height: 320)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)], startPoint: .center, endPoint: .bottom))

            HStack(alignment: .top, spacing: 28) {
                Color.clear
                    .frame(width: 200, height: 300)
                    .overlay { RemoteImage(url: jellyfin.posterURL(item, height: 750), maxPixel: 500) { Rectangle().fill(.quaternary) } }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 10)
                    .offset(y: -100)
                    .padding(.bottom, -100)

                VStack(alignment: .leading, spacing: 14) {
                    Text(item.name).font(.largeTitle.weight(.bold)).textSelection(.enabled)
                    content()
                }
            }
            .padding(.horizontal, 32)
        }
    }
}

private struct MetaLine: View {
    let item: JFItem

    var body: some View {
        HStack(spacing: 12) {
            if let year = item.year { Text(String(year)) }
            if let minutes = item.runtimeMinutes, item.type == "Movie" { Text("\(minutes) Min.") }
            if let official = item.officialRating {
                Text(official)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary))
            }
            if let rating = item.communityRating { Label(String(format: "%.1f", rating), systemImage: "star.fill") }
            if let genres = item.genres, !genres.isEmpty { Text(genres.prefix(3).joined(separator: ", ")).lineLimit(1) }
        }
        .foregroundStyle(.secondary)
    }
}

private struct WatchedFavoriteButtons: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    let item: JFItem

    var body: some View {
        Button {
            Task { await jellyfin.setPlayed(item, !item.isPlayed) }
        } label: {
            Label(item.isPlayed ? "Gesehen" : "Als gesehen markieren",
                  systemImage: item.isPlayed ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .controlSize(.large)
        .help(item.isPlayed ? "Als ungesehen markieren" : "Als gesehen markieren")

        Button {
            Task { await jellyfin.setFavorite(item, !item.isFavorite) }
        } label: {
            Image(systemName: item.isFavorite ? "star.fill" : "star")
        }
        .controlSize(.large)
        .help(item.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen")
    }
}

struct JellyfinFilmDetailView: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    let itemId: String
    let fallback: JFItem

    var body: some View {
        // The list copy carries current user data; the detail copy adds people and streams.
        let listed = jellyfin.films.first { $0.id == itemId } ?? fallback
        var item = jellyfin.details[itemId] ?? listed
        item.userData = listed.userData ?? item.userData
        return ScrollView {
            JellyfinDetailHeader(item: item) {
                MetaLine(item: item)
                HStack(spacing: 12) {
                    JellyfinPlayButton(item: item)
                    WatchedFavoriteButtons(item: item)
                }
                if let progress = item.progress {
                    ProgressView(value: progress).frame(maxWidth: 320)
                }
                if let overview = item.overview {
                    Text(overview).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: 720, alignment: .leading)
                }
                PeopleAndStreams(item: item)
            }
            .padding(.bottom, 32)
        }
        .safeAreaInset(edge: .top, spacing: 0) { JellyfinStatusBanner() }
        .navigationTitle(item.name)
        .task(id: itemId) { await jellyfin.loadDetail(itemId) }
    }
}

private struct PeopleAndStreams: View {
    let item: JFItem

    var body: some View {
        let people = item.people ?? []
        let directors = people.filter { $0.type == "Director" }.map(\.name)
        let cast = people.filter { $0.type == "Actor" }.prefix(10).map(\.name)
        if !directors.isEmpty {
            LabeledContent("Regie") { Text(directors.joined(separator: ", ")).foregroundStyle(.secondary) }
        }
        if !cast.isEmpty {
            LabeledContent("Besetzung") { Text(cast.joined(separator: ", ")).foregroundStyle(.secondary) }
        }
        ForEach(Array((item.mediaSources ?? []).enumerated()), id: \.offset) { index, source in
            let streams = source.mediaStreams ?? []
            let audio = streams.filter { $0.type == "Audio" }.compactMap { $0.displayTitle ?? $0.language }
            let subtitles = streams.filter { $0.type == "Subtitle" }.compactMap { $0.displayTitle ?? $0.language }
            VStack(alignment: .leading, spacing: 4) {
                if (item.mediaSources?.count ?? 0) > 1 {
                    Text(source.name ?? String(localized: "Version \(index + 1)")).font(.headline)
                }
                if !audio.isEmpty {
                    LabeledContent("Tonspuren") { Text(audio.joined(separator: " · ")).foregroundStyle(.secondary) }
                }
                if !subtitles.isEmpty {
                    LabeledContent("Untertitel") { Text(subtitles.joined(separator: " · ")).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

struct JellyfinSeriesDetailView: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    @EnvironmentObject private var app: AppModel
    let seriesId: String
    let fallback: JFItem
    @State private var seasonId: String?

    var body: some View {
        let listed = jellyfin.series.first { $0.id == seriesId } ?? fallback
        var item = jellyfin.details[seriesId] ?? listed
        item.userData = listed.userData ?? item.userData
        let seasons = jellyfin.seasons[seriesId] ?? []
        return ScrollView {
            JellyfinDetailHeader(item: item) {
                MetaLine(item: item)
                HStack(spacing: 12) {
                    JellyfinPlayButton(item: item)
                    WatchedFavoriteButtons(item: item)
                }
                if let overview = item.overview {
                    Text(overview).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: 720, alignment: .leading)
                }
                PeopleAndStreams(item: item)
            }
            episodesSection(seasons)
                .padding(32)
        }
        .safeAreaInset(edge: .top, spacing: 0) { JellyfinStatusBanner() }
        .navigationTitle(item.name)
        .task(id: seriesId) {
            async let detail: Void = jellyfin.loadDetail(seriesId)
            async let list: Void = jellyfin.loadSeasons(seriesId)
            _ = await (detail, list)
            if seasonId == nil {
                let loaded = jellyfin.seasons[seriesId] ?? []
                // Start with the first season that still has unwatched episodes.
                seasonId = (loaded.first { !$0.isPlayed } ?? loaded.first)?.id
            }
        }
        .task(id: seasonId) {
            if let seasonId { await jellyfin.loadEpisodes(seriesId: seriesId, seasonId: seasonId) }
        }
    }

    @ViewBuilder
    private func episodesSection(_ seasons: [JFItem]) -> some View {
        if seasons.isEmpty {
            ProgressView().frame(maxWidth: .infinity)
        } else if let seasonId, let season = seasons.first(where: { $0.id == seasonId }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    if seasons.count > 1 {
                        Picker("Staffel", selection: Binding(get: { seasonId }, set: { self.seasonId = $0 })) {
                            ForEach(seasons) { Text($0.name).tag($0.id) }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                    } else {
                        Text(season.name).font(.title2.weight(.semibold))
                    }
                    Spacer()
                    Button(season.isPlayed ? "Staffel als ungesehen markieren" : "Staffel als gesehen markieren") {
                        Task { await jellyfin.setPlayed(season, !season.isPlayed) }
                    }
                }
                LazyVStack(spacing: 10) {
                    ForEach(jellyfin.episodes[seasonId] ?? []) { episode in
                        JellyfinEpisodeRow(episode: episode)
                            .contentShape(Rectangle())
                            .onTapGesture { app.play(jellyfin: episode) }
                            .contextMenu { JellyfinItemMenu(item: episode) }
                    }
                }
            }
        }
    }
}

struct JellyfinEpisodeRow: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    let episode: JFItem

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Color.clear
                .frame(width: 200, height: 112)
                .overlay {
                    RemoteImage(url: jellyfin.thumbURL(episode), maxPixel: 400) {
                        ZStack {
                            Rectangle().fill(.quaternary)
                            Image(systemName: "play.rectangle").font(.title).foregroundStyle(.tertiary)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                if let progress = episode.progress {
                    ProgressView(value: progress).progressViewStyle(.linear).padding(6)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let number = episode.indexNumber {
                        Text("\(number). \(episode.name)").font(.headline).lineLimit(1)
                    } else {
                        Text(episode.name).font(.headline).lineLimit(1)
                    }
                    if episode.isPlayed {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).accessibilityLabel("Gesehen")
                    }
                    Spacer()
                    if let minutes = episode.runtimeMinutes, minutes > 0 {
                        Text("\(minutes) Min.").foregroundStyle(.secondary).font(.callout)
                    }
                    Button {
                        Task { await jellyfin.setPlayed(episode, !episode.isPlayed) }
                    } label: {
                        Image(systemName: episode.isPlayed ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.borderless)
                    .help(episode.isPlayed ? "Als ungesehen markieren" : "Als gesehen markieren")
                }
                if let overview = episode.overview {
                    Text(overview).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
        .padding(10)
    }
}

// MARK: - Home

struct JellyfinHomeView: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !jellyfin.resume.isEmpty {
                    row("Weiterschauen", items: jellyfin.resume, landscape: true)
                }
                if !jellyfin.nextUp.isEmpty {
                    row("Nächste Folge", items: jellyfin.nextUp, landscape: true)
                }
                if !jellyfin.latestFilms.isEmpty {
                    row("Neue Filme", items: jellyfin.latestFilms, landscape: false)
                }
                if !jellyfin.latestSeries.isEmpty {
                    row("Neue Serien", items: jellyfin.latestSeries, landscape: false)
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .top, spacing: 0) { JellyfinStatusBanner() }
        .overlay {
            if jellyfin.resume.isEmpty && jellyfin.nextUp.isEmpty && jellyfin.latestFilms.isEmpty && jellyfin.latestSeries.isEmpty {
                if jellyfin.isLoading { ProgressView() } else { ContentUnavailableView("Noch nichts zu sehen", systemImage: "house") }
            }
        }
        .navigationTitle(jellyfin.session?.serverName ?? "Jellyfin")
        .task { await jellyfin.refreshHome() }
    }

    private func row(_ title: LocalizedStringKey, items: [JFItem], landscape: Bool) -> some View {
        // Room for two title lines, year and rating under a poster; title and episode under a still.
        JellyfinCarousel(title: title, items: items, itemWidth: landscape ? 280 : 160, height: landscape ? 210 : 320) { item in
            if landscape {
                // Continue Watching / Next Up: a click plays.
                Button { app.play(jellyfin: item) } label: { landscapeCard(item) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        JellyfinItemMenu(item: item)
                        if let series = jellyfin.seriesItem(for: item), item.type == "Episode" {
                            NavigationLink("Serie öffnen", value: series)
                        }
                    }
            } else {
                NavigationLink(value: item) {
                    // Natural height: with the row's height the 2:3 poster would shrink for two-line titles.
                    JellyfinPoster(item: item).frame(width: 160).fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .contextMenu { JellyfinItemMenu(item: item) }
            }
        }
    }

    private func landscapeCard(_ item: JFItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .frame(width: 280, height: 158)
                .overlay { RemoteImage(url: jellyfin.thumbURL(item), maxPixel: 600) { Rectangle().fill(.quaternary) } }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottom) {
                    if let progress = item.progress {
                        ProgressView(value: progress).progressViewStyle(.linear).padding(8)
                    }
                }
            Text(item.seriesName ?? item.name).font(.callout.weight(.medium)).lineLimit(1)
            if item.type == "Episode" {
                Text(episodeLabel(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 280)
    }

    private func episodeLabel(_ item: JFItem) -> String {
        let code = [item.parentIndexNumber.map { "S\($0)" }, item.indexNumber.map { "E\($0)" }].compactMap { $0 }.joined()
        return code.isEmpty ? item.name : "\(code) · \(item.name)"
    }
}

/// A horizontal row that can also be paged with buttons (no horizontal scroll wheel needed).
private struct JellyfinCarousel<Card: View>: View {
    let title: LocalizedStringKey
    let items: [JFItem]
    let itemWidth: CGFloat
    /// Fixed row height: lazy rows otherwise size to the first cards and clip taller ones.
    let height: CGFloat
    @ViewBuilder let card: (JFItem) -> Card

    @State private var position: String?
    @State private var visibleCount = 4
    private let spacing: CGFloat = 18

    var body: some View {
        let index = position.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.title2.weight(.semibold))
                Spacer()
                Button { page(from: index, by: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(index == 0)
                    .help("Zurück")
                Button { page(from: index, by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(index + visibleCount >= items.count)
                    .help("Weiter")
            }
            .buttonStyle(.borderless)
            .font(.title3)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: spacing) {
                    ForEach(items) { item in
                        card(item).frame(width: itemWidth)
                    }
                }
                .scrollTargetLayout()
            }
            .frame(height: height)
            .scrollPosition(id: $position, anchor: .leading)
            .scrollTargetBehavior(.viewAligned)
            .onGeometryChange(for: Int.self) { geo in
                max(1, Int((geo.size.width + spacing) / (itemWidth + spacing)))
            } action: { visibleCount = $0 }
        }
    }

    private func page(from index: Int, by direction: Int) {
        let target = min(max(0, index + direction * visibleCount), max(0, items.count - visibleCount))
        withAnimation(.snappy) { position = items[target].id }
    }
}
