import FernsyCore
import FernsyPlayer
import SwiftUI

/// A page the library screens open: a film or series of either source.
enum DetailTarget: Hashable {
    case movie(Movie)
    case series(Series)
    case jellyfin(JFItem)

    static func of(_ target: LibraryEntry.Target) -> DetailTarget? {
        switch target {
        case .movie(let movie): .movie(movie)
        case .series(let series), .episode(_, let series): .series(series)
        case .jellyfin(let item): item.type == "Episode" ? nil : .jellyfin(item)
        case .recording: nil
        }
    }
}

/// The page for a target: film page or series page.
struct DetailPage: View {
    let target: DetailTarget

    var body: some View {
        switch target {
        case .movie(let movie): FilmPage(film: .iptv(movie))
        case .series(let series): SeriesPage(show: .iptv(series))
        case .jellyfin(let item):
            if item.type == "Series" { SeriesPage(show: .jellyfin(item)) } else { FilmPage(film: .jellyfin(item)) }
        }
    }
}

// MARK: Cards

/// A 2:3 poster with its title, rating, "New", progress and watched mark.
struct PosterCard: View {
    let title: String
    let image: URL?
    var rating: Double?
    var isNew = false
    var progress: Double?
    var watched = false
    var badge: String?
    var badgeColor: Color = Color(hex: 0x6C65F0)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { RemoteImage(url: image, maxPixel: 500) { ArtPlaceholder(seed: title) } }
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if isNew { Tag(text: Text("New"), background: TVTheme.accent, foreground: .white).padding(6) }
                    else if let badge { Tag(text: Text(verbatim: badge), background: badgeColor, foreground: .white).padding(6) }
                }
                .overlay(alignment: .topTrailing) {
                    if watched {
                        Image(systemName: "checkmark").font(.caption2.weight(.heavy))
                            .frame(width: 22, height: 22).background(Color(hex: 0x6C65F0), in: .circle).padding(6)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let progress, progress > 0, !watched { ProgressBar(value: progress).frame(height: 4).padding(6) }
                }
            Text(verbatim: title).font(.footnote.weight(.semibold)).lineLimit(2)
            if let rating, rating > 0 {
                Text(verbatim: "★ \(rating.formatted(.number.precision(.fractionLength(1))))").font(.caption2).foregroundStyle(TVTheme.tertiary)
            }
        }
        .contentShape(.rect)
    }
}

/// A 16:9 card with title, detail, source and progress (Continue Watching, episodes).
struct WideCard: View {
    let title: String
    let detail: String
    let image: URL?
    var source: String?
    var progress: Double?
    var watched = false
    var upNext = false
    var width: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { RemoteImage(url: image, maxPixel: 600) { ArtPlaceholder(seed: title) } }
                .clipShape(.rect(cornerRadius: 10))
                .overlay(alignment: .topLeading) {
                    if upNext { Tag(text: Text("Up Next"), background: .white, foreground: TVTheme.focusedText).padding(6) }
                    else if let source { Tag(text: Text(verbatim: source), background: Color(hex: 0x0F0E12, opacity: 0.65), foreground: .white).padding(6) }
                }
                .overlay(alignment: .topTrailing) {
                    if watched {
                        Image(systemName: "checkmark").font(.caption2.weight(.heavy))
                            .frame(width: 22, height: 22).background(Color(hex: 0x6C65F0), in: .circle).padding(6)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let progress, progress > 0 { ProgressBar(value: progress).frame(height: 4).padding(8) }
                }
            Text(verbatim: title).font(.subheadline.weight(.semibold)).lineLimit(1)
            if !detail.isEmpty { Text(verbatim: detail).font(.caption).foregroundStyle(TVTheme.tertiary).lineLimit(1) }
        }
        .frame(width: width, alignment: .leading)
        .contentShape(.rect)
    }
}

struct Tag: View {
    let text: Text
    let background: Color
    let foreground: Color

    var body: some View {
        text.font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(background, in: .rect(cornerRadius: 5))
            .foregroundStyle(foreground)
    }
}

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule().fill(TVTheme.accentLight).frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
    }
}

/// A row title with an optional note ("Favorites", "Jellyfin").
struct RowTitle: View {
    let title: LocalizedStringKey
    var note: LocalizedStringKey?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.title3.bold())
            if let note { Text(note).font(.subheadline).foregroundStyle(TVTheme.tertiary) }
        }
        .padding(.horizontal, 16)
    }
}

/// A row of cards that scrolls sideways.
struct CardRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) { content }
                .padding(.horizontal, 16)
        }
    }
}

/// Minutes as the design writes them: "2 hr 4 min", "48 min".
enum Runtime {
    static func text(seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? String(localized: "\(minutes / 60) hr \(minutes % 60) min") : String(localized: "\(minutes) min")
    }
}

// MARK: Grid

/// Films or series of the IPTV account: a poster grid that fits the width, with a category
/// picker and the sorting.
struct LibraryGridView: View {
    enum Kind { case movies, series }
    enum Sort: CaseIterable { case added, name, rating, year }

    @EnvironmentObject private var model: TVModel
    let kind: Kind
    @State private var category: XCategory?
    @State private var sort: Sort = .added
    @State private var debugDetail: DetailTarget?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 12, alignment: .top)], alignment: .leading, spacing: 18) {
                switch kind {
                case .movies:
                    ForEach(sortedMovies) { movie in
                        NavigationLink(value: DetailTarget.movie(movie)) {
                            PosterCard(title: movie.name, image: movie.poster.flatMap(URL.init(string:)), rating: movie.rating,
                                       isNew: LibraryRules.isNew(added: movie.added),
                                       progress: model.resume.fraction(ResumeStore.movieKey(movie.id)),
                                       watched: model.resume.isWatched(ResumeStore.movieKey(movie.id)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("movie.\(movie.id)")
                    }
                case .series:
                    ForEach(sortedSeries) { show in
                        NavigationLink(value: DetailTarget.series(show)) {
                            PosterCard(title: show.name, image: show.cover.flatMap(URL.init(string:)), rating: show.rating,
                                       isNew: LibraryRules.isNew(added: show.lastModified))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("series.\(show.id)")
                    }
                }
            }
            .padding(16)
            if (kind == .movies ? model.movies.isEmpty : model.series.isEmpty) {
                ProgressView().padding(40)
            }
        }
        .background(TVTheme.background.ignoresSafeArea())
        .navigationTitle(kind == .movies ? "Movies" : "Series")
        .navigationDestination(for: DetailTarget.self) { DetailPage(target: $0) }
        .navigationDestination(item: $debugDetail) { DetailPage(target: $0) }
        #if DEBUG
        // IPTV_DETAIL=movie:<id>|series:<id>: opens that page (screenshots without touch input).
        .task(id: model.movies.count + model.series.count) {
            guard debugDetail == nil, let spec = ProcessInfo.processInfo.environment["IPTV_DETAIL"] else { return }
            let parts = spec.split(separator: ":")
            guard parts.count == 2, let id = Int(parts[1]) else { return }
            if parts[0] == "movie", kind == .movies, let movie = model.movies.first(where: { $0.id == id }) { debugDetail = .movie(movie) }
            if parts[0] == "series", kind == .series, let show = model.series.first(where: { $0.id == id }) { debugDetail = .series(show) }
        }
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Category", selection: $category) {
                        Text("All").tag(XCategory?.none)
                        ForEach(categories) { item in Text(verbatim: item.displayName).tag(Optional(item)) }
                    }
                    .accessibilityIdentifier("grid.category")
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { value in Text(Self.title(value)).tag(value) }
                    }
                    .accessibilityIdentifier("grid.sort")
                } label: {
                    Label("Category and Sorting", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var categories: [XCategory] { kind == .movies ? model.movieCategories : model.seriesCategories }

    static func title(_ sort: Sort) -> LocalizedStringKey {
        switch sort {
        case .added: "Recently Added"
        case .name: "A–Z"
        case .rating: "Rating"
        case .year: "Release Year"
        }
    }

    private var sortedMovies: [Movie] {
        let list = model.movies.filter { category == nil || $0.categoryId == category?.id }
        switch sort {
        case .added, .year: return list.sorted { $0.added > $1.added }
        case .name: return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .rating: return list.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        }
    }

    private var sortedSeries: [Series] {
        let list = model.series.filter { category == nil || $0.categoryId == category?.id }
        switch sort {
        case .added: return list.sorted { $0.lastModified > $1.lastModified }
        case .name: return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .rating: return list.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .year: return list.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
        }
    }
}

// MARK: Film page

/// A film page for an IPTV or Jellyfin film: backdrop, facts, description, Resume (or Play),
/// From the Beginning, favourite, and director, cast and tracks.
struct FilmPage: View {
    enum Film { case iptv(Movie), jellyfin(JFItem) }

    @EnvironmentObject private var model: TVModel
    let film: Film
    @State private var details: MovieDetails?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay { RemoteImage(url: backdrop, maxPixel: 1400) { ArtPlaceholder(seed: title) } }
                    .clipped()
                    .overlay { LinearGradient(colors: [.clear, TVTheme.background], startPoint: .center, endPoint: .bottom) }
                VStack(alignment: .leading, spacing: 14) {
                    Text(verbatim: title).font(.largeTitle.bold()).lineLimit(3)
                    HStack(spacing: 8) {
                        Text(verbatim: facts.joined(separator: " · "))
                        if let rating = jfItem?.officialRating {
                            Text(verbatim: rating).font(.caption.weight(.bold)).padding(.horizontal, 5)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.4)))
                        }
                    }
                    .font(.subheadline).foregroundStyle(TVTheme.secondary)
                    HStack(spacing: 10) {
                        Button { play(fromStart: false) } label: {
                            Label(position > 0 ? "Resume · \(Duration.seconds(position).formatted(.time(pattern: .hourMinuteSecond)))" : "Play",
                                  systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ActionButtonStyle())
                        .accessibilityIdentifier("film.play")
                        Button { toggleFavorite() } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star").foregroundStyle(isFavorite ? TVTheme.favorite : TVTheme.text)
                                .frame(width: 20)
                        }
                        .buttonStyle(ActionButtonStyle(prominent: false))
                        .accessibilityIdentifier("film.favorite")
                    }
                    if position > 0 {
                        Button { play(fromStart: true) } label: { Text("From the Beginning").frame(maxWidth: .infinity) }
                            .buttonStyle(ActionButtonStyle(prominent: false))
                            .accessibilityIdentifier("film.fromStart")
                        if duration > 0 {
                            HStack(spacing: 10) {
                                ProgressBar(value: position / duration).frame(width: 140, height: 4)
                                Text(String(localized: "\(Int(((duration - position) / 60).rounded())) min left"))
                            }
                            .font(.caption).foregroundStyle(TVTheme.tertiary)
                        }
                    }
                    if let overview, !overview.isEmpty {
                        Text(verbatim: overview).foregroundStyle(TVTheme.secondary)
                    }
                    ForEach(factEntries.indices, id: \.self) { index in
                        let (key, value) = factEntries[index]
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key).font(.caption.weight(.bold)).foregroundStyle(TVTheme.tertiary)
                            Text(verbatim: value).font(.subheadline)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .padding(.bottom, 30)
        }
        .ignoresSafeArea(edges: .top)
        .background(TVTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            switch film {
            case .iptv(let movie): details = await model.movieDetails(movie)
            case .jellyfin(let item): await model.jellyfin.loadDetail(item.id)
            }
        }
    }

    private var jfItem: JFItem? {
        if case .jellyfin(let item) = film { return model.jellyfin.details[item.id] ?? item }
        return nil
    }

    private var title: String {
        switch film {
        case .iptv(let movie): movie.name
        case .jellyfin(let item): item.name
        }
    }

    private var backdrop: URL? {
        switch film {
        case .iptv(let movie): (details?.backdrop ?? details?.poster ?? movie.poster).flatMap(URL.init(string:))
        case .jellyfin(let item): (model.jellyfin.backdropURL(jfItem ?? item) ?? model.jellyfin.posterURL(item)).flatMap(URL.init(string:))
        }
    }

    private var overview: String? { jfItem?.overview ?? details?.plot }

    private var facts: [String] {
        var list: [String] = []
        if let item = jfItem {
            if let year = item.productionYear { list.append("\(year)") }
            if let genre = item.genres?.first { list.append(genre) }
            if let ticks = item.runTimeTicks { list.append(Runtime.text(seconds: Double(ticks) / 10_000_000)) }
            if let rating = item.communityRating { list.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
        } else if case .iptv(let movie) = film {
            if let year = details?.releaseDate?.prefix(4), !year.isEmpty { list.append(String(year)) }
            if let genre = details?.genre?.split(separator: ",").first { list.append(String(genre).trimmingCharacters(in: .whitespaces)) }
            if let duration = details?.duration, !duration.isEmpty { list.append(duration) }
            if let rating = movie.rating, rating > 0 { list.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
        }
        return list
    }

    private var position: Double {
        switch film {
        case .iptv(let movie): model.resume.position(ResumeStore.movieKey(movie.id))
        case .jellyfin(let item): Double((jfItem ?? item).userData?.playbackPositionTicks ?? 0) / 10_000_000
        }
    }

    private var duration: Double {
        switch film {
        case .iptv(let movie):
            let key = ResumeStore.movieKey(movie.id)
            return model.resume.fraction(key).map { model.resume.position(key) / $0 } ?? 0
        case .jellyfin(let item): return Double((jfItem ?? item).runTimeTicks ?? 0) / 10_000_000
        }
    }

    private var isFavorite: Bool {
        switch film {
        case .iptv(let movie): model.isFavorite(movie: movie)
        case .jellyfin(let item): (jfItem ?? item).userData?.isFavorite == true
        }
    }

    private func toggleFavorite() {
        switch film {
        case .iptv(let movie): model.toggleFavorite(key: LibraryRules.favoriteKey(movie: movie.id))
        case .jellyfin(let item): Task { await model.jellyfin.setFavorite(jfItem ?? item, !isFavorite) }
        }
    }

    private func play(fromStart: Bool) {
        switch film {
        case .iptv(let movie): model.play(.movie(movie), fromStart: fromStart)
        case .jellyfin(let item): model.play(.jellyfin(jfItem ?? item), fromStart: fromStart)
        }
    }

    private var factEntries: [(LocalizedStringKey, String)] {
        var list: [(LocalizedStringKey, String)] = []
        if let item = jfItem {
            if let director = item.people?.first(where: { $0.type == "Director" })?.name { list.append(("DIRECTOR", director)) }
            let cast = (item.people ?? []).filter { $0.type == "Actor" }.prefix(3).map(\.name)
            if !cast.isEmpty { list.append(("CAST", cast.joined(separator: ", "))) }
            let streams = item.mediaSources?.first?.mediaStreams ?? []
            let audio = Array(Set(streams.filter { $0.type == "Audio" }.compactMap { $0.language.map(LanguageChoice.name) }))
            if !audio.isEmpty { list.append(("AUDIO", audio.sorted().joined(separator: ", "))) }
            let subs = Array(Set(streams.filter { $0.type == "Subtitle" }.compactMap { $0.language.map(LanguageChoice.name) }))
            if !subs.isEmpty { list.append(("SUBTITLES", subs.sorted().joined(separator: ", "))) }
        } else {
            if let director = details?.director, !director.isEmpty { list.append(("DIRECTOR", director)) }
            if let cast = details?.cast, !cast.isEmpty { list.append(("CAST", cast)) }
        }
        return list
    }
}

// MARK: Series page

/// A series page for an IPTV or Jellyfin series: source, seasons, "Next Episode", favourite, a
/// season picker and the season's episodes.
struct SeriesPage: View {
    enum Show { case iptv(Series), jellyfin(JFItem) }

    @EnvironmentObject private var model: TVModel
    let show: Show
    @State private var info: SeriesInfo?
    @State private var season: String?

    struct EpisodeEntry: Identifiable {
        let id: String
        let title: String
        let number: String
        let label: String
        let image: URL?
        let progress: Double?
        let watched: Bool
        let item: VODItem
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay { RemoteImage(url: backdrop, maxPixel: 1400) { ArtPlaceholder(seed: title) } }
                    .clipped()
                    .overlay { LinearGradient(colors: [.clear, TVTheme.background], startPoint: .center, endPoint: .bottom) }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Tag(text: Text(verbatim: sourceName), background: TVTheme.accentLight.opacity(0.3), foreground: Color(hex: 0xDAD8FF))
                        Text(seasonKeys.count == 1 ? "Series · 1 season" : "Series · \(seasonKeys.count) seasons")
                            .font(.subheadline).foregroundStyle(TVTheme.secondary)
                    }
                    Text(verbatim: title).font(.largeTitle.bold()).lineLimit(3)
                    HStack(spacing: 10) {
                        if let next = nextEpisode {
                            Button { model.play(next.item) } label: {
                                Label("Next Episode · \(next.label)", systemImage: "play.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ActionButtonStyle())
                            .accessibilityIdentifier("series.next")
                        }
                        Button { toggleFavorite() } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star").foregroundStyle(isFavorite ? TVTheme.favorite : TVTheme.text)
                                .frame(width: 20)
                        }
                        .buttonStyle(ActionButtonStyle(prominent: false))
                    }
                    if let overview, !overview.isEmpty {
                        Text(verbatim: overview).foregroundStyle(TVTheme.secondary).lineLimit(6)
                    }
                    if seasonKeys.count > 1 {
                        Picker("Season", selection: Binding(get: { currentSeason ?? "" }, set: { season = $0 })) {
                            ForEach(seasonKeys, id: \.self) { key in Text(seasonTitle(key)).tag(key) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("series.season")
                    }
                }
                .padding(.horizontal, 16)
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(episodes) { episode in
                        Button { model.play(episode.item) } label: {
                            HStack(spacing: 12) {
                                WideCard(title: "", detail: "", image: episode.image, progress: episode.progress,
                                         watched: episode.watched, upNext: episode.id == nextEpisode?.id, width: 150)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: episode.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(verbatim: episode.number).font(.caption).foregroundStyle(TVTheme.tertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("episode.\(episode.id)")
                        .accessibilityValue(episode.id == nextEpisode?.id ? "next" : episode.watched ? "watched" : "")
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 30)
        }
        .ignoresSafeArea(edges: .top)
        .background(TVTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: season) { _, value in
            if case .jellyfin(let item) = show, let value { Task { await model.jellyfin.loadEpisodes(seriesId: item.id, seasonId: value) } }
        }
    }

    private func load() async {
        switch show {
        case .iptv(let series):
            info = await model.seriesDetails(series)
            if season == nil, let next = nextEpisode, case .episode(let episode, _) = next.item { season = String(episode.season) }
        case .jellyfin(let item):
            await model.jellyfin.loadSeasons(item.id)
            let next = await model.jellyfin.episodeToPlay(seriesId: item.id)
            if season == nil { season = next?.seasonId ?? model.jellyfin.seasons[item.id]?.first?.id }
            if let season { await model.jellyfin.loadEpisodes(seriesId: item.id, seasonId: season) }
        }
    }

    private var title: String {
        switch show {
        case .iptv(let series): series.name
        case .jellyfin(let item): item.name
        }
    }

    private var sourceName: String {
        if case .jellyfin = show { return "JELLYFIN" }
        return "IPTV"
    }

    private var overview: String? {
        switch show {
        case .iptv(let series): series.plot
        case .jellyfin(let item): (model.jellyfin.details[item.id] ?? item).overview
        }
    }

    private var backdrop: URL? {
        switch show {
        case .iptv(let series): (info?.backdrop ?? series.cover).flatMap(URL.init(string:))
        case .jellyfin(let item): (model.jellyfin.backdropURL(item) ?? model.jellyfin.posterURL(item)).flatMap(URL.init(string:))
        }
    }

    private var seasonKeys: [String] {
        switch show {
        case .iptv: (info?.seasons.keys.sorted() ?? []).map(String.init)
        case .jellyfin(let item): (model.jellyfin.seasons[item.id] ?? []).map(\.id)
        }
    }

    private var currentSeason: String? { season ?? seasonKeys.first }

    private func seasonTitle(_ key: String) -> String {
        switch show {
        case .iptv: String(localized: "Season \(Int(key) ?? 0)")
        case .jellyfin(let item): model.jellyfin.seasons[item.id]?.first { $0.id == key }?.name ?? key
        }
    }

    private var episodes: [EpisodeEntry] {
        switch show {
        case .iptv(let series):
            guard let key = currentSeason.flatMap(Int.init) else { return [] }
            return (info?.seasons[key] ?? []).map { Self.entry($0, series, model) }
        case .jellyfin:
            guard let key = currentSeason else { return [] }
            return (model.jellyfin.episodes[key] ?? []).map(Self.entry)
        }
    }

    private static func entry(_ episode: Episode, _ series: Series, _ model: TVModel) -> EpisodeEntry {
        let key = "episode.\(episode.id)"
        let runtime = episode.durationSeconds.map { " · " + Runtime.text(seconds: Double($0)) } ?? ""
        return EpisodeEntry(id: episode.id, title: episode.title, number: "S\(episode.season) F\(episode.number)\(runtime)",
                            label: "S\(episode.season) F\(episode.number)", image: (episode.image ?? series.cover).flatMap(URL.init(string:)),
                            progress: model.resume.fraction(key), watched: model.resume.isWatched(key), item: .episode(episode, series))
    }

    private static func entry(_ item: JFItem) -> EpisodeEntry {
        let runtime = item.runTimeTicks.map { " · " + Runtime.text(seconds: Double($0) / 10_000_000) } ?? ""
        let label = "S\(item.parentIndexNumber ?? 0) F\(item.indexNumber ?? 0)"
        let share = item.userData?.playedPercentage.map { $0 / 100 }
        return EpisodeEntry(id: item.id, title: item.name, number: label + runtime, label: label,
                            image: TVModel.shared.jellyfin.thumbURL(item).flatMap(URL.init(string:)),
                            progress: share.flatMap { $0 > 0 ? $0 : nil }, watched: item.userData?.played == true, item: .jellyfin(item))
    }

    /// The episode to continue with: Jellyfin's Next Up, or the IPTV rule (TVModel.nextEpisode).
    private var nextEpisode: EpisodeEntry? {
        switch show {
        case .iptv(let series):
            guard let info, let episode = model.nextEpisode(of: series, in: info) else { return nil }
            return Self.entry(episode, series, model)
        case .jellyfin(let item):
            if let next = model.jellyfin.nextUp.first(where: { $0.seriesId == item.id }) { return Self.entry(next) }
            return episodes.first { !$0.watched }
        }
    }

    private var isFavorite: Bool {
        switch show {
        case .iptv(let series): model.isFavorite(series: series)
        case .jellyfin(let item): (model.jellyfin.details[item.id] ?? item).userData?.isFavorite == true
        }
    }

    private func toggleFavorite() {
        switch show {
        case .iptv(let series): model.toggleFavorite(key: LibraryRules.favoriteKey(series: series.id))
        case .jellyfin(let item): Task { await model.jellyfin.setFavorite(model.jellyfin.details[item.id] ?? item, !isFavorite) }
        }
    }
}
