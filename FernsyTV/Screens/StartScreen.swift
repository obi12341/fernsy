import FernsyCore
import FernsyPlayer
import SwiftUI

/// Start (design screen `home`): the newest item to continue as a large entry, then "Continue
/// Watching" across IPTV, Jellyfin and recordings, and "Recently Added" from IPTV and Jellyfin.
struct StartScreen: View {
    @EnvironmentObject private var model: TVModel
    @State private var path: [DetailTarget] = []

    var body: some View {
        NavigationStack(path: $path) {
            let resume = model.continueWatching
            let added = model.recentlyAdded
            ScrollView {
                VStack(alignment: .leading, spacing: 50) {
                    if let hero = resume.first {
                        Hero(entry: hero) { open(hero) } info: { info(hero) }
                    }
                    if !resume.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            RowTitle(title: "Continue Watching")
                            CardRow {
                                ForEach(resume) { entry in
                                    Button { open(entry) } label: {
                                        WideCard(title: entry.title, detail: entry.detail, image: entry.image,
                                                 source: Self.sourceName(entry.source), progress: entry.progress)
                                    }
                                    .buttonStyle(.borderless)
                                    .contextMenu { if DetailTarget.of(entry.open) != nil { Button("Details", systemImage: "info.circle") { info(entry) } } }
                                    .accessibilityIdentifier("start.resume.\(entry.id)")
                                }
                            }
                        }
                    }
                    if !added.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            RowTitle(title: "Recently Added", note: "IPTV and Jellyfin")
                            CardRow {
                                ForEach(added) { entry in
                                    Button { info(entry) } label: {
                                        PosterCard(title: entry.title, image: entry.image, badge: Self.sourceName(entry.source),
                                                   badgeColor: entry.source == .jellyfin ? Color(hex: 0x6C65F0) : Color(hex: 0x0F0E12, opacity: 0.65))
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("start.added.\(entry.id)")
                                }
                            }
                        }
                    }
                    if resume.isEmpty && added.isEmpty {
                        Text("Your films and series appear here once the library has loaded.")
                            .font(.system(size: 26)).foregroundStyle(TVTheme.secondary)
                    }
                }
                .padding(.horizontal, 90)
                .padding(.bottom, 60)
            }
            .background {
                // The newest item's backdrop fills the screen behind the tab bar, as in the design.
                ZStack {
                    TVTheme.background
                    if let hero = resume.first {
                        RemoteImage(url: Hero.backdrop(hero, model), maxPixel: 1920) { ArtPlaceholder(seed: hero.title) }
                            .frame(width: 1920, height: 1080).clipped()
                        LinearGradient(stops: [.init(color: TVTheme.background.opacity(0.88), location: 0), .init(color: TVTheme.background.opacity(0.4), location: 0.42),
                                               .init(color: .clear, location: 0.7)], startPoint: .leading, endPoint: .trailing)
                        LinearGradient(stops: [.init(color: TVTheme.background, location: 0), .init(color: TVTheme.background, location: 0.34),
                                               .init(color: .clear, location: 0.64)], startPoint: .bottom, endPoint: .top)
                    }
                }
                .ignoresSafeArea()
            }
            .foregroundStyle(TVTheme.text)
            .navigationDestination(for: DetailTarget.self) { DetailScreen(target: $0) }
            .task(id: model.jellyfin.session?.userId) { if model.jellyfin.session != nil { await model.jellyfin.refreshHome() } }
        }
    }

    static func sourceName(_ source: LibraryEntry.Source) -> String {
        switch source {
        case .iptv: "IPTV"
        case .jellyfin: "Jellyfin"
        case .recording: String(localized: "Recording")
        }
    }

    /// Click resumes; films and series without a position open their page.
    private func open(_ entry: LibraryEntry) {
        switch entry.open {
        case .movie(let movie): model.play(.movie(movie))
        case .episode(let episode, let series): model.play(.episode(episode, series))
        case .jellyfin(let item): model.play(.jellyfin(item))
        case .recording(let recording): model.play(recording)
        case .series: info(entry)
        }
    }

    private func info(_ entry: LibraryEntry) {
        if case .jellyfin(let item) = entry.open, item.type == "Episode", let seriesId = item.seriesId {
            path.append(.jellyfin(model.jellyfin.series.first { $0.id == seriesId } ?? item))
        } else if let target = DetailTarget.of(entry.open) {
            path.append(target)
        }
    }
}

/// The large "Continue Watching" entry over the backdrop (the screen's background).
private struct Hero: View {
    @EnvironmentObject private var model: TVModel
    let entry: LibraryEntry
    let resume: () -> Void
    let info: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("CONTINUE WATCHING · \(kind)").font(.system(size: 22, weight: .bold)).tracking(1.6).foregroundStyle(TVTheme.text.opacity(0.75))
            Text(verbatim: entry.title).font(.system(size: 84, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            if !facts.isEmpty {
                Text(verbatim: facts).font(.system(size: 26)).foregroundStyle(TVTheme.text.opacity(0.8))
            }
            HStack(spacing: 20) {
                Button(action: resume) {
                    Label(entry.detail.isEmpty ? String(localized: "Resume") : String(localized: "Resume · \(entry.detail)"), systemImage: "play.fill")
                }
                .buttonStyle(ActionButtonStyle())
                .accessibilityIdentifier("start.hero.resume")
                if DetailTarget.of(entry.open) != nil {
                    Button(action: info) { Image(systemName: "info.circle") }
                        .buttonStyle(ActionButtonStyle(round: true))
                        .accessibilityIdentifier("start.hero.info")
                }
            }
            .padding(.top, 14)
        }
        .frame(width: 1100, alignment: .leading)
        .padding(.top, 90)
        .padding(.bottom, 40)
        .focusSection()
    }

    /// "2024 · Drama · 2 hr 4 min · ★ 7.3", as far as known.
    private var facts: String {
        var list: [String] = []
        switch entry.open {
        case .jellyfin(let item):
            if item.type == "Episode" { if let subtitle = VODItem.jellyfin(item).subtitle { list.append(subtitle) } } else {
                if let year = item.productionYear { list.append("\(year)") }
                if let genre = item.genres?.first { list.append(genre) }
                if let ticks = item.runTimeTicks { list.append(Runtime.text(seconds: Double(ticks) / 10_000_000)) }
                if let rating = item.communityRating { list.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
            }
        case .movie(let movie):
            if let details = model.movieInfo[movie.id] {
                if let year = details.releaseDate?.prefix(4), !year.isEmpty { list.append(String(year)) }
                if let genre = details.genre?.split(separator: ",").first { list.append(String(genre)) }
            }
            if let rating = movie.rating, rating > 0 { list.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
        case .episode(let episode, _): list.append("S\(episode.season) F\(episode.number) · \(episode.title)")
        default: break
        }
        return list.joined(separator: " · ")
    }

    private var kind: String {
        switch entry.open {
        case .movie: String(localized: "FILM")
        case .series, .episode: String(localized: "SERIES")
        case .jellyfin(let item): item.type == "Episode" ? String(localized: "SERIES") : String(localized: "FILM")
        case .recording: String(localized: "RECORDING")
        }
    }

    static func backdrop(_ entry: LibraryEntry, _ model: TVModel) -> URL? {
        switch entry.open {
        case .movie(let movie): model.movieInfo[movie.id]?.backdrop.flatMap(URL.init(string:)) ?? entry.image
        case .jellyfin(let item): model.jellyfin.backdropURL(item).flatMap(URL.init(string:)) ?? entry.image
        default: entry.image
        }
    }
}

/// Films or series of the IPTV account (design screen `filme`): a poster grid with a category
/// picker and the sorting.
struct LibraryGridScreen: View {
    enum Kind { case movies, series }
    enum Sort: CaseIterable { case added, name, rating, year }

    @EnvironmentObject private var model: TVModel
    let kind: Kind
    @State private var category: XCategory?
    @State private var sort: Sort = .added

    var body: some View {
        NavigationStack {
            // The header scrolls with the grid: outside it, Up from the first row went straight to
            // the tab bar and the category and sorting could not be reached.
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(spacing: 20) {
                        Text(kind == .movies ? "Films" : "Series").font(.system(size: 44, weight: .bold)).padding(.trailing, 12)
                        Menu {
                            Button("All") { category = nil }
                            ForEach(categories) { item in Button(item.displayName) { category = item } }
                        } label: {
                            Text("Category: \(category?.displayName ?? String(localized: "All"))").font(.system(size: 23, weight: .semibold))
                        }
                        .accessibilityIdentifier("grid.category")
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach(Sort.allCases, id: \.self) { value in
                                Button { sort = value } label: { Text(Self.title(value)).font(.system(size: 22, weight: .semibold)).padding(.horizontal, 22).frame(height: 46) }
                                    .buttonStyle(SortStyle(selected: sort == value))
                                    .accessibilityIdentifier("grid.sort.\(value)")
                            }
                        }
                        .padding(6)
                        .background(Color.white.opacity(0.08), in: .capsule)
                    }
                    .focusSection()
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(200), spacing: 56), count: 7), alignment: .leading, spacing: 44) {
                        switch kind {
                        case .movies:
                            ForEach(sortedMovies) { movie in
                                NavigationLink(value: DetailTarget.movie(movie)) {
                                    PosterCard(title: movie.name, image: movie.poster.flatMap(URL.init(string:)), rating: movie.rating,
                                               isNew: LibraryRules.isNew(added: movie.added),
                                               progress: model.resume.fraction(ResumeStore.movieKey(movie.id)),
                                               watched: model.resume.isWatched(ResumeStore.movieKey(movie.id)))
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("movie.\(movie.id)")
                            }
                        case .series:
                            ForEach(sortedSeries) { show in
                                NavigationLink(value: DetailTarget.series(show)) {
                                    PosterCard(title: show.name, image: show.cover.flatMap(URL.init(string:)), rating: show.rating,
                                               isNew: LibraryRules.isNew(added: show.lastModified))
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("series.\(show.id)")
                            }
                        }
                    }
                    .padding(.vertical, 20)
                    .focusSection()
                }
                .padding(.top, 10)
            }
            .scrollClipDisabled()
            .padding(.horizontal, 90)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TVTheme.background.ignoresSafeArea())
            .foregroundStyle(TVTheme.text)
            .navigationDestination(for: DetailTarget.self) { DetailScreen(target: $0) }
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

private struct SortStyle: ButtonStyle {
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
