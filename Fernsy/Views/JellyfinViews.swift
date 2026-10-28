import FernsyCore
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
        case .added: return String(localized: "Recently Added")
        case .name: return String(localized: "Name")
        case .release: return String(localized: "Release Date")
        case .rating: return String(localized: "Rating")
        }
    }

    /// For the segmented control.
    var shortTitle: String {
        switch self {
        case .added: return String(localized: "Added")
        case .name: return String(localized: "Name")
        case .release: return String(localized: "Release")
        case .rating: return String(localized: "Rating")
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
        var rows = [CategoryRow(id: "favorites", name: String(localized: "Favorites"), count: all.filter(\.isFavorite).count)]
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

    func filtered(_ kind: JFKind, categoryID: String, sort: JFSort) -> [JFItem] {
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

/// Offline, expired session and failed writes, above every Jellyfin view – the same notice as
/// Live TV's "provider not reachable".
struct JellyfinStatusBanner: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    @State private var signingIn = false

    var body: some View {
        VStack(spacing: 6) {
            if jellyfin.isExpired {
                notice(title: "Jellyfin Session Expired", detail: "Sign in again to keep watching.") {
                    Button("Sign In Again") { signingIn = true }
                }
            } else if jellyfin.isOffline {
                notice(title: "Jellyfin Not Reachable", detail: "You are seeing the saved library.") {
                    Button("Try Again") { Task { await jellyfin.loadLibrary(forceRefresh: true) } }
                        .disabled(jellyfin.isLoading)
                }
            }
            if let error = jellyfin.lastError {
                notice(title: "Jellyfin", detail: LocalizedStringKey(error)) {
                    Button("OK") { jellyfin.lastError = nil }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, jellyfin.isExpired || jellyfin.isOffline || jellyfin.lastError != nil ? 6 : 0)
        .sheet(isPresented: $signingIn) {
            JellyfinSignInForm(prefillServer: jellyfin.session?.server, prefillUser: jellyfin.session?.userName) { signingIn = false }
                .padding(24)
        }
    }

    private func notice(title: LocalizedStringKey, detail: LocalizedStringKey, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            action()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.warning.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct JellyfinPlayButton: View {
    @EnvironmentObject private var app: AppModel
    let item: JFItem

    var body: some View {
        let resume = item.isSeries ? 0 : Double(item.userData?.playbackPositionTicks ?? 0) / 10_000_000
        Button {
            app.play(jellyfin: item)
        } label: {
            Label(resume > 0 ? "Resume (\(formatTime(resume)))" : "Play", systemImage: "play.fill")
                .padding(.horizontal, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        if resume > 0 {
            Button("Start Over") { app.play(jellyfin: item, resume: false) }
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
            Button("Play") { app.play(jellyfin: item) }
            Divider()
        }
        Button(item.isPlayed ? "Mark as Unwatched" : "Mark as Watched") {
            Task { await jellyfin.setPlayed(item, !item.isPlayed) }
        }
        if item.type == "Movie" || item.isSeries {
            Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
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
    @AppStorage("jellyfin.sort.films") private var filmSort: JFSort = .added
    @AppStorage("jellyfin.sort.series") private var seriesSort: JFSort = .added

    private var sort: Binding<JFSort> { kind == .films ? $filmSort : $seriesSort }

    var body: some View {
        let list = jellyfin.filtered(kind, categoryID: categoryID, sort: sort.wrappedValue)
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
            if jellyfin.items(kind).isEmpty && jellyfin.isLoading {
                ProgressView("Loading library …")
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Sort Order", selection: sort) {
                    ForEach(JFSort.allCases) { Text($0.shortTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Sort Order")
            }
        }
        .navigationTitle(kind == .films ? "Movies" : "Series")
        .navigationSubtitle(kind == .films ? "\(list.count) movies" : "\(list.count) series")
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

/// Backdrop (under the toolbar), poster, title and a slot for the content below – the same
/// layout as the IPTV film and series pages.
private struct JellyfinDetailHeader<Content: View>: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    let item: JFItem
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailBackdrop(url: jellyfin.backdropURL(item, height: 1080))

            HStack(alignment: .top, spacing: 28) {
                Color.clear
                    .frame(width: 200, height: 300)
                    .overlay { RemoteImage(url: jellyfin.posterURL(item, height: 750), maxPixel: 500) { Rectangle().fill(.quaternary) } }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                    .offset(y: -120)
                    .padding(.bottom, -120)

                VStack(alignment: .leading, spacing: 14) {
                    Text(verbatim: item.name).font(.largeTitle.weight(.bold)).textSelection(.enabled)
                    content()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 36)
        }
    }
}

private struct MetaLine: View {
    let item: JFItem

    var body: some View {
        let parts = [item.year.map(String.init), item.type == "Movie" ? item.runtimeMinutes.flatMap { runtimeText("\($0)") } : nil,
                     item.officialRating, item.communityRating.map { "★ \($0.formatted(.number.precision(.fractionLength(1))))" },
                     item.genres.flatMap { $0.isEmpty ? nil : $0.prefix(3).joined(separator: ", ") }].compactMap { $0 }
        Text(verbatim: parts.joined(separator: " · "))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct WatchedFavoriteButtons: View {
    @EnvironmentObject private var jellyfin: JellyfinStore
    let item: JFItem

    var body: some View {
        Button {
            Task { await jellyfin.setPlayed(item, !item.isPlayed) }
        } label: {
            Label(item.isPlayed ? "Watched" : "Mark as Watched",
                  systemImage: item.isPlayed ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .controlSize(.large)
        .help(item.isPlayed ? "Mark as Unwatched" : "Mark as Watched")

        Button {
            Task { await jellyfin.setFavorite(item, !item.isFavorite) }
        } label: {
            Image(systemName: item.isFavorite ? "star.fill" : "star")
        }
        .controlSize(.large)
        .help(item.isFavorite ? "Remove from Favorites" : "Add to Favorites")
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
        .ignoresSafeArea(edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .overlay(alignment: .top) { JellyfinStatusBanner().padding(.top, 52) }
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
            LabeledContent("Director") { Text(directors.joined(separator: ", ")).foregroundStyle(.secondary) }
        }
        if !cast.isEmpty {
            LabeledContent("Cast") { Text(cast.joined(separator: ", ")).foregroundStyle(.secondary) }
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
                    LabeledContent("Audio Tracks") { Text(audio.joined(separator: " · ")).foregroundStyle(.secondary) }
                }
                if !subtitles.isEmpty {
                    LabeledContent("Subtitles") { Text(subtitles.joined(separator: " · ")).foregroundStyle(.secondary) }
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
        .ignoresSafeArea(edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .overlay(alignment: .top) { JellyfinStatusBanner().padding(.top, 52) }
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
                        let picker = Picker("Season", selection: Binding(get: { seasonId }, set: { self.seasonId = $0 })) {
                            ForEach(seasons) { Text(verbatim: $0.name).tag($0.id) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        // A segment like the IPTV series page; a menu once there are too many seasons.
                        if seasons.count <= 6 { picker.pickerStyle(.segmented) } else { picker.pickerStyle(.menu) }
                    } else {
                        Text(season.name).font(.title2.weight(.semibold))
                    }
                    Spacer()
                    Button(season.isPlayed ? "Mark Season as Unwatched" : "Mark Season as Watched") {
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
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).accessibilityLabel("Watched")
                    }
                    Spacer()
                    if let minutes = episode.runtimeMinutes, minutes > 0 {
                        Text("\(minutes) min").foregroundStyle(.secondary).font(.callout)
                    }
                    Button {
                        Task { await jellyfin.setPlayed(episode, !episode.isPlayed) }
                    } label: {
                        Image(systemName: episode.isPlayed ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.borderless)
                    .help(episode.isPlayed ? "Mark as Unwatched" : "Mark as Watched")
                }
                if let overview = episode.overview {
                    Text(overview).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
        .padding(10)
    }
}
