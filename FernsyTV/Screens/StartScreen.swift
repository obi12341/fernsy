import FernsyCore
import FernsyPlayer
import SwiftUI

/// Start (design screen `home`, tvos-start-rows): the newest item to continue (or else the newest
/// film) as a large entry, then live channels, Continue Watching, Next Up, tonight's shows,
/// Recently Added, the largest categories and genres, recordings and best rated films. Each row
/// shows only with entries.
struct StartScreen: View {
    @EnvironmentObject private var model: TVModel
    @State private var path: [DetailTarget] = []
    @State private var rows = StartRows()
    @State private var asked: (show: EPGEntry, channel: LiveChannel)?
    /// How far Start is scrolled, read only by the backdrop (tvos-start-scrolling design 1).
    @State private var scroll = StartScroll()

    var body: some View {
        NavigationStack(path: $path) {
            // Everything shown comes from `rows`, built when its inputs change (design 2):
            // nothing here walks the catalog, so a redraw stays cheap.
            let resume = rows.resume
            let added = rows.added
            let hero = resume.first ?? rows.spotlight
            let live = rows.live
            let tonight = rows.tonight
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 50) {
                    if let hero {
                        Hero(entry: hero, spotlight: resume.isEmpty, scroll: scroll) { open(hero) } info: { info(hero) }
                    }
                    if !live.channels.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            RowTitle(title: "On Now", note: live.source == .favorites ? "Favorites" : live.source == .recent ? "Recently Watched" : nil)
                            CardRow {
                                ForEach(live.channels) { channel in
                                    Button {
                                        model.zapSource = live.source
                                        model.play(channel)
                                    } label: {
                                        StartLiveCard(channel: channel, guide: model.guide.guide(channel.id))
                                    }
                                    .buttonStyle(TVTileStyle(radius: 20, scale: 1.05))
                                    .accessibilityIdentifier("start.live.\(channel.id)")
                                }
                            }
                        }
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
                    wideRow("Next Up", note: "Jellyfin", id: "next", rows.nextUp)
                    if !tonight.shows.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            RowTitle(title: LocalizedStringKey(tonight.title))
                            CardRow {
                                ForEach(tonight.shows, id: \.channel.id) { item in
                                    Button { pick(item.show, on: item.channel) } label: {
                                        StartShowCard(show: item.show, channel: item.channel,
                                                      scheduled: model.isScheduled(item.show, on: item.channel))
                                    }
                                    .buttonStyle(TVTileStyle(radius: 20, scale: 1.05))
                                    .accessibilityIdentifier("start.tonight.\(item.channel.id)")
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
                    ForEach(rows.categories) { row in posterRow(row.title, id: row.id, row.entries) }
                    wideRow("Your Recordings", note: nil, id: "recordings", rows.recordings)
                    posterRow(String(localized: "Best Rated"), id: "best", rows.bestRated)
                    if resume.isEmpty && added.isEmpty {
                        Text("Your movies and series appear here once the library has loaded.")
                            .font(.system(size: 26)).foregroundStyle(TVTheme.secondary)
                    }
                }
                .padding(.horizontal, 90)
                .padding(.bottom, 60)
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, value in scroll.update(value) }
            .background { StartBackdrop(hero: hero, scroll: scroll) }
            .foregroundStyle(TVTheme.text)
            .navigationDestination(for: DetailTarget.self) { DetailScreen(target: $0) }
            .task(id: model.jellyfin.session?.userId) { if model.jellyfin.session != nil { await model.jellyfin.refreshHome() } }
            // Rows from the catalog once per change of it, not per redraw (design A).
            .task(id: "\(model.movies.count).\(model.series.count).\(model.jellyfin.films.count).\(model.jellyfin.latestFilms.count)") {
                let catalog = model.startRows()
                rows.spotlight = catalog.spotlight
                rows.categories = catalog.categories
                rows.bestRated = catalog.bestRated
                rows.added = catalog.added
                refreshResume()
                if case .movie(let movie)? = rows.spotlight?.open { _ = await model.movieDetails(movie) }
            }
            // Continue Watching, Next Up and recordings: on return to Start, when the player
            // closes, when positions arrive from iCloud, and when Jellyfin or the recorder change.
            .onAppear { refreshResume(); refreshLive() }
            .onChange(of: resumeInputs) { refreshResume() }
            // On Now and Tonight: favourites, recently watched, hidden channels; again once their guides loaded.
            .onChange(of: liveInputs) { refreshLive() }
            .task(id: live.channels.map(\.id)) {
                for channel in live.channels { await model.loadGuide(for: channel) }
                rows.tonight = model.tonight(on: rows.live.channels)
            }
            .confirmationDialog(asked.map { $0.show.title } ?? "", isPresented: Binding(get: { asked != nil }, set: { if !$0 { asked = nil } }),
                                presenting: asked) { item in
                if model.isScheduled(item.show, on: item.channel) {
                    Button("Don’t Record", role: .destructive) { model.recorder.unschedule(channelId: item.channel.id, entry: item.show) }
                } else {
                    Button("Record") { model.notice = model.schedule(item.show, on: item.channel) }
                }
            } message: { item in
                Text("\(item.channel.displayName) · \(TimeSpan.of(item.show)). Records only while Fernsy is open.")
            }
        }
    }

    /// What Continue Watching, Next Up and the recordings read: the player closing, positions
    /// from iCloud, Jellyfin's lists and the recorder's.
    private var resumeInputs: String {
        let playing = model.playingVOD != nil || model.playingRecording != nil
        let jellyfin = (model.jellyfin.resume + model.jellyfin.nextUp).map(\.id).joined(separator: ",")
        let recordings = model.recorder.recordings.map { "\($0.id)\($0.status)" }.joined(separator: ",")
        return "\(playing)|\(model.resumeRevision)|\(jellyfin)|\(recordings)"
    }

    /// What On Now reads: favourites, recently watched, the channel list and hidden channels.
    private var liveInputs: String {
        "\(model.favorites.sorted())|\(model.recentChannels).\(model.channels.count).\(model.visibility.modifiedAt.timeIntervalSince1970)"
    }

    private func refreshResume() {
        rows.resume = model.continueWatching
        rows.nextUp = model.nextUpEntries
        rows.recordings = model.recordingEntries
    }

    private func refreshLive() {
        rows.live = model.startChannels
        rows.tonight = model.tonight(on: rows.live.channels)
    }

    /// A running show plays its channel; a later one offers to record it.
    private func pick(_ show: EPGEntry, on channel: LiveChannel) {
        if show.start <= Date() {
            model.zapSource = rows.live.source
            model.play(channel)
        } else {
            asked = (show, channel)
        }
    }

    @ViewBuilder private func posterRow(_ title: String, id: String, _ entries: [LibraryEntry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                RowTitle(title: LocalizedStringKey(title))
                CardRow {
                    ForEach(entries) { entry in
                        Button { info(entry) } label: {
                            PosterCard(title: entry.title, image: entry.image,
                                       rating: { if case .movie(let movie) = entry.open { movie.rating } else { nil } }(),
                                       badge: entry.source == .jellyfin ? "Jellyfin" : nil, badgeColor: Color(hex: 0x6C65F0))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("start.\(id).\(entry.id)")
                    }
                }
            }
        }
    }

    @ViewBuilder private func wideRow(_ title: LocalizedStringKey, note: LocalizedStringKey?, id: String, _ entries: [LibraryEntry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                RowTitle(title: title, note: note)
                CardRow {
                    ForEach(entries) { entry in
                        Button { open(entry) } label: {
                            WideCard(title: entry.title, detail: entry.detail, image: entry.image,
                                     source: Self.sourceName(entry.source), progress: entry.progress)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("start.\(id).\(entry.id)")
                    }
                }
            }
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

/// A live channel on Start: logo, the show on now with its progress and time left.
private struct StartLiveCard: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel
    /// Observed, so the card shows the show once the guide arrives.
    @ObservedObject var guide: ChannelGuide
    @Environment(\.isFocused) private var focused

    var body: some View {
        let show = model.currentShow(on: channel)
        HStack(spacing: 18) {
            ChannelLogo(channel: channel, radius: 12).frame(width: 112, height: 70)
            VStack(alignment: .leading, spacing: 7) {
                Text(verbatim: channel.displayName).font(.system(size: 20, weight: .semibold)).opacity(0.7).lineLimit(1)
                Text(verbatim: show?.title ?? String(localized: "No program information")).font(.system(size: 24, weight: .semibold)).lineLimit(1)
                if let show {
                    HStack(spacing: 12) {
                        ShowProgress(show: show, focused: focused).frame(width: 120, height: 5)
                        Text("\(max(1, Int((show.end.timeIntervalSinceNow / 60).rounded(.up)))) min left").font(.system(size: 18).monospacedDigit()).opacity(0.6)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 470, height: 124, alignment: .leading)
    }
}

/// A show of tonight on Start: time, channel and title, marked when it is to be recorded.
private struct StartShowCard: View {
    let show: EPGEntry
    let channel: LiveChannel
    let scheduled: Bool

    var body: some View {
        HStack(spacing: 18) {
            ChannelLogo(channel: channel, radius: 12).frame(width: 96, height: 60)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if scheduled { RecordingMark() }
                    Text(show.start, format: .dateTime.hour().minute()).font(.system(size: 20, weight: .bold).monospacedDigit())
                    Text(verbatim: channel.displayName).font(.system(size: 19)).opacity(0.6).lineLimit(1)
                }
                Text(verbatim: show.title).font(.system(size: 24, weight: .semibold)).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 440, height: 124, alignment: .leading)
    }
}

/// The large "Continue Watching" entry over the backdrop (the screen's background).
private struct Hero: View {
    @EnvironmentObject private var model: TVModel
    let entry: LibraryEntry
    /// Nothing to continue: the newest film, offered to play.
    var spotlight = false
    /// Told whether a button here has focus, so the backdrop moves (tvos-living-hero design 2).
    let scroll: StartScroll
    let resume: () -> Void
    let info: () -> Void
    @FocusState private var focus: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // A new entry's text eases in (design 5); the buttons keep their identity so focus stays.
            VStack(alignment: .leading, spacing: 18) {
                Text(spotlight ? "NEW · \(kind)" : "CONTINUE WATCHING · \(kind)").font(.system(size: 22, weight: .bold)).tracking(1.6).foregroundStyle(TVTheme.text.opacity(0.75))
                Text(verbatim: entry.title).font(.system(size: 84, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                if !facts.isEmpty {
                    Text(verbatim: facts).font(.system(size: 26)).foregroundStyle(TVTheme.text.opacity(0.8))
                }
            }
            .id(entry.id)
            .transition(.opacity.combined(with: .offset(y: 12)))
            HStack(spacing: 20) {
                Button(action: resume) {
                    if spotlight {
                        Label("Play", systemImage: "play.fill")
                    } else {
                        Label(entry.detail.isEmpty ? String(localized: "Resume") : String(localized: "Resume · \(entry.detail)"), systemImage: "play.fill")
                    }
                }
                .buttonStyle(ActionButtonStyle())
                .focused($focus, equals: true)
                .accessibilityIdentifier("start.hero.resume")
                if DetailTarget.of(entry.open) != nil {
                    Button(action: info) { Image(systemName: "info.circle") }
                        .buttonStyle(ActionButtonStyle(round: true))
                        .focused($focus, equals: false)
                        .accessibilityIdentifier("start.hero.info")
                }
            }
            .padding(.top, 14)
        }
        .animation(.easeOut(duration: 0.5), value: entry.id)
        .onChange(of: focus != nil, initial: true) { _, focused in scroll.heroFocused = focused }
        .onDisappear { scroll.heroFocused = false }
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
        case .movie: String(localized: "MOVIE")
        case .series, .episode: String(localized: "SERIES")
        case .jellyfin(let item): item.type == "Episode" ? String(localized: "SERIES") : String(localized: "MOVIE")
        case .recording: String(localized: "RECORDING")
        }
    }

    /// All of the title's backdrops (tvos-living-hero design 3), else its picture.
    static func backdrops(_ entry: LibraryEntry, _ model: TVModel) -> [URL] {
        let list: [String] = switch entry.open {
        case .movie(let movie): model.movieInfo[movie.id]?.backdrops ?? []
        case .series(let series), .episode(_, let series): model.seriesInfo[series.id]?.backdrops ?? []
        case .jellyfin(let item): model.jellyfin.backdropURLs(item)
        case .recording: []
        }
        let urls = list.prefix(5).compactMap(URL.init(string:))
        return urls.isEmpty ? entry.image.map { [$0] } ?? [] : urls
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
                        Text(kind == .movies ? "Movies" : "Series").font(.system(size: 44, weight: .bold)).padding(.trailing, 12)
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

/// The scroll offset for the backdrop's fade, in 12-point steps (2 % of opacity), and whether the
/// large entry has focus: only StartBackdrop reads them, so scrolling and focus redraw the
/// backdrop, not the rows (tvos-start-scrolling, tvos-living-hero).
@Observable
final class StartScroll {
    private(set) var offset: CGFloat = 0
    var heroFocused = false

    func update(_ value: CGFloat) {
        let stepped = (min(max(value, 0), 600) / 12).rounded() * 12
        if stepped != offset { offset = stepped }
    }
}

/// The newest item's backdrop behind Start and the tab bar, as in the design; it gives way to
/// the rows below the large entry.
private struct StartBackdrop: View {
    @EnvironmentObject private var model: TVModel
    let hero: LibraryEntry?
    let scroll: StartScroll

    var body: some View {
        ZStack {
            TVTheme.background
            if let hero {
                LivingBackdrop(urls: Hero.backdrops(hero, model), active: scroll.heroFocused, seed: hero.title)
                    .frame(width: 1920, height: 1080).clipped()
                    .accessibilityElement()
                    .accessibilityIdentifier("start.backdrop")
                    .accessibilityValue(scroll.heroFocused ? "moving" : "resting")
                    .opacity(max(0.15, 1 - scroll.offset / 600))
                LinearGradient(stops: [.init(color: TVTheme.background.opacity(0.88), location: 0), .init(color: TVTheme.background.opacity(0.4), location: 0.42),
                                       .init(color: .clear, location: 0.7)], startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [.init(color: TVTheme.background, location: 0), .init(color: TVTheme.background, location: 0.34),
                                       .init(color: .clear, location: 0.64)], startPoint: .bottom, endPoint: .top)
            }
        }
        .ignoresSafeArea()
    }
}
