import FernsyCore
import FernsyPlayer
import SwiftUI

/// Start on the Mac (mac-start-pages): the rows of Start on Apple TV from the same rules
/// (FernsyCore `StartBuilder`), with the Mac's cards, the player window and the detail pages.
struct StartView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var jellyfin: JellyfinStore
    @EnvironmentObject private var recorder: Recorder
    /// Rows kept in state and rebuilt when their inputs change, never while drawing (design 7).
    @State private var rows = StartRows()
    @State private var asked: TonightItem?
    #if DEBUG
    private static var debugAsked = false
    #endif

    var body: some View {
        let hero = rows.resume.first ?? rows.spotlight
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                if let hero {
                    StartBanner(entry: hero, spotlight: rows.resume.isEmpty, open: { open(hero) })
                }
                if !rows.live.channels.isEmpty {
                    PagingCarousel(title: Text("On Now"), note: liveNote, items: rows.live.channels, itemWidth: 300, height: 92) { channel in
                        Button { app.play(channel) } label: { StartLiveCard(channel: channel, guide: app.epg.guide(channel.id)) }
                            .buttonStyle(.plain)
                            .help("Watch \(channel.displayName)")
                    }
                }
                wideRow(Text("Continue Watching"), rows.resume)
                wideRow(Text("Next Up"), note: Text(verbatim: "Jellyfin"), rows.nextUp)
                if !rows.tonight.shows.isEmpty {
                    PagingCarousel(title: Text(verbatim: rows.tonight.title), items: rows.tonight.shows.map(TonightItem.init), itemWidth: 300, height: 92) { item in
                        Button { pick(item) } label: { StartShowCard(item: item, scheduled: isScheduled(item)) }
                            .buttonStyle(.plain)
                    }
                }
                posterRow(Text("Recently Added"), note: Text("IPTV and Jellyfin"), rows.added)
                ForEach(rows.categories) { row in posterRow(Text(verbatim: row.title), row.entries) }
                wideRow(Text("Your Recordings"), rows.recordings)
                posterRow(Text("Best Rated"), rows.bestRated)
                if hero == nil && rows.added.isEmpty {
                    Text("Your movies and series appear here once the library has loaded.")
                        .font(.title3).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .navigationTitle(LibrarySection.start.title)
        // Rows from the catalog once per change of it, not per redraw.
        .task(id: "\(app.movies.count).\(app.series.count).\(jellyfin.films.count).\(jellyfin.latestFilms.count).\(jellyfin.latestSeries.count)") {
            let catalog = builder.catalogRows()
            rows.spotlight = catalog.spotlight
            rows.categories = catalog.categories
            rows.bestRated = catalog.bestRated
            rows.added = catalog.added
        }
        .task { await jellyfin.refreshHome() }
        .onAppear(perform: refreshPersonal)
        .onChange(of: personalInputs) { refreshPersonal() }
        // The live rows' guides, then tonight's shows on those channels. While Start is shown
        // the guides stay fresh and tonight's row follows the clock (start-live-clock).
        .task(id: rows.live.channels.map(\.id)) {
            let channels = rows.live.channels
            for channel in channels { await app.epg.load(channel.id, client: app.client) }
            refreshTonight()
            await withTaskGroup(of: Void.self) { group in
                for channel in channels {
                    group.addTask { @MainActor in await app.epg.keepFresh(channel.id, client: app.client) }
                }
                group.addTask { @MainActor in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(LiveClock.secondsToNextMinute()))
                        if !Task.isCancelled { refreshTonight() }
                    }
                }
            }
        }
        .confirmationDialog(asked.map { $0.show.title } ?? "", isPresented: Binding(get: { asked != nil }, set: { if !$0 { asked = nil } }),
                            presenting: asked) { item in
            Button("Record") { recorder.schedule(item.show, on: item.channel).present() }
            ServerRecordItem(app: app, entry: item.show, channel: item.channel)
            Button("Watch Live") { app.play(item.channel) }
        } message: { item in
            Text(verbatim: "\(item.channel.displayName) · \(item.show.start.formatted(date: .omitted, time: .shortened))–\(item.show.end.formatted(date: .omitted, time: .shortened))")
        }
    }

    // MARK: Data

    private var builder: StartBuilder {
        var builder = StartBuilder()
        builder.movies = app.showsIPTVMovies ? app.movies : []
        builder.series = app.showsIPTVSeries ? app.series : []
        builder.movieCategories = app.movieCategories
        builder.seriesCategories = app.seriesCategories
        builder.addJellyfin(jellyfin)
        builder.resume = app.resume
        builder.episodeIndex = app.episodeIndex
        builder.recordings = recorder.recordings.map(StartBuilder.recording)
        builder.channels = app.channels
        return builder
    }

    /// Continue Watching, Next Up, recordings and the live channels: on return to Start, when
    /// the catalog loads, when the player closes, when positions arrive (iCloud), when Jellyfin or
    /// the recorder change, and when favourites change.
    private var personalInputs: String {
        let recordings = recorder.recordings.map { "\($0.id)\($0.status)" }.joined(separator: ",")
        return "\(app.movies.count).\(app.series.count).\(app.channels.count).\(app.resumeRevision).\(app.nowPlaying == nil)."
            + "\(jellyfin.homeRevision).\(recordings).\(app.favorites.count).\(app.recentChannels)"
    }

    private func refreshPersonal() {
        let builder = builder
        rows.resume = builder.continueWatching()
        rows.nextUp = builder.nextUp()
        rows.recordings = builder.finishedRecordings()
        rows.live = StartBuilder.liveChannels(favorites: app.filteredChannels(categoryID: favoriteChannelsID, query: ""),
                                              recent: app.filteredChannels(categoryID: recentChannelsID, query: ""),
                                              all: app.filteredChannels(categoryID: allCategoryID, query: ""))
    }

    private func refreshTonight() {
        rows.tonight = StartBuilder.tonight(on: rows.live.channels, guide: { app.epg.guide($0).entries ?? [] }, now: LiveClock.now())
        #if DEBUG
        // IPTV_TESTSTARTASK=1: opens the record question of tonight's first later show once, for a
        // screenshot (the Mac app has no UI test target).
        if ProcessInfo.processInfo.environment["IPTV_TESTSTARTASK"] != nil, !Self.debugAsked,
           let item = rows.tonight.shows.map(TonightItem.init).first(where: { $0.show.start > Date() }) {
            Self.debugAsked = true
            // Later: a question asked while the window is still opening is not shown.
            Task { try? await Task.sleep(for: .seconds(3)); asked = item }
        }
        #endif
    }

    private var liveNote: Text? {
        switch rows.live.source {
        case .favorites: Text("Favorites")
        case .recent: Text("Recently Watched")
        default: nil
        }
    }

    // MARK: Rows

    @ViewBuilder private func wideRow(_ title: Text, note: Text? = nil, _ entries: [LibraryEntry]) -> some View {
        if !entries.isEmpty {
            PagingCarousel(title: title, note: note, items: entries, itemWidth: 280, height: 210) { entry in
                Button { open(entry) } label: { StartWideCard(entry: entry) }
                    .buttonStyle(.plain)
                    .contextMenu { menu(entry) }
            }
        }
    }

    @ViewBuilder private func posterRow(_ title: Text, note: Text? = nil, _ entries: [LibraryEntry]) -> some View {
        if !entries.isEmpty {
            PagingCarousel(title: title, note: note, items: entries, itemWidth: 160, height: 320) { entry in
                pageLink(entry) {
                    PosterCard(title: entry.title, imageURL: entry.image?.absoluteString, rating: rating(entry),
                               subtitle: Self.sourceName(entry.source))
                        .frame(width: 160).fixedSize(horizontal: false, vertical: true)
                }
                .contextMenu { menu(entry) }
            }
        }
    }

    /// A poster opens its page; one without a page (a recording) plays.
    @ViewBuilder private func pageLink(_ entry: LibraryEntry, @ViewBuilder label: () -> some View) -> some View {
        switch entry.open {
        case .movie(let movie): NavigationLink(value: movie, label: label).buttonStyle(.plain)
        case .series(let series), .episode(_, let series): NavigationLink(value: series, label: label).buttonStyle(.plain)
        case .jellyfin(let item): NavigationLink(value: item, label: label).buttonStyle(.plain)
        case .recording: Button(action: { open(entry) }, label: label).buttonStyle(.plain)
        }
    }

    @ViewBuilder private func menu(_ entry: LibraryEntry) -> some View {
        if case .series = entry.open {} else { Button("Play", systemImage: "play.fill") { open(entry) } }
        switch entry.open {
        case .movie(let movie): NavigationLink("Details", value: movie)
        case .series(let series), .episode(_, let series): NavigationLink("Open Series", value: series)
        case .jellyfin(let item):
            if let series = jellyfin.seriesItem(for: item), item.type == "Episode" {
                NavigationLink("Open Series", value: series)
            } else {
                NavigationLink("Details", value: item)
            }
        case .recording: EmptyView()
        }
    }

    // MARK: Actions

    /// Plays from where the user stopped.
    private func open(_ entry: LibraryEntry) {
        switch entry.open {
        case .movie(let movie): app.play(movie)
        case .episode(let episode, let series): app.play(episode, of: series)
        case .jellyfin(let item): app.play(jellyfin: item)
        case .recording(let id): if let recording = recorder.recordings.first(where: { $0.id == id }) { app.play(recording) }
        case .series: break   // a series opens its page (the poster's link), it has nothing to play
        }
    }

    private func pick(_ item: TonightItem) {
        let now = Date()
        if item.show.start <= now && now < item.show.end { app.play(item.channel) } else { asked = item }
    }

    private func isScheduled(_ item: TonightItem) -> Bool {
        recorder.recording(channelId: item.channel.id, entry: item.show)?.isUpcomingOrRunning == true
    }

    private func rating(_ entry: LibraryEntry) -> Double? {
        switch entry.open {
        case .movie(let movie): movie.rating
        case .series(let series): series.rating
        case .jellyfin(let item): item.communityRating
        default: nil
        }
    }

    static func sourceName(_ source: LibraryEntry.Source) -> String {
        switch source {
        case .iptv: "IPTV"
        case .jellyfin: "Jellyfin"
        case .recording: String(localized: "Recorded")
        }
    }
}

/// A show of Heute Abend with its channel, identified by the channel (one show each).
struct TonightItem: Identifiable {
    let show: EPGEntry
    let channel: LiveChannel
    var id: Int { channel.id }

    init(_ pair: (show: EPGEntry, channel: LiveChannel)) {
        show = pair.show
        channel = pair.channel
    }
}

// MARK: - Large entry

/// The newest item to continue (or the newest film) over its backdrop, which moves while the
/// pointer is over it (design 5).
private struct StartBanner: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var jellyfin: JellyfinStore
    let entry: LibraryEntry
    /// Nothing to continue: the newest film, offered to play.
    let spotlight: Bool
    let open: () -> Void
    @State private var hovering = false
    @State private var backdrops: [URL] = []

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LivingBackdrop(urls: backdrops, active: hovering || Self.testHover)
                // As tall as fits: in a small window the title and buttons stay in view.
                .containerRelativeFrame(.vertical) { height, _ in min(400, max(240, height * 0.62)) }
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(stops: [.init(color: .black.opacity(0.85), location: 0), .init(color: .black.opacity(0.35), location: 0.5),
                                   .init(color: .clear, location: 0.85)], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 10) {
                Text(spotlight ? "NEW · \(kind)" : "CONTINUE WATCHING · \(kind)")
                    .font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.white.opacity(0.75))
                Text(verbatim: entry.title).font(.system(size: 40, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                if !facts.isEmpty { Text(verbatim: facts).font(.title3).foregroundStyle(.white.opacity(0.8)) }
                HStack(spacing: 12) {
                    Button(action: open) {
                        if spotlight || entry.detail.isEmpty || entry.detail == "IPTV" || entry.detail == "Jellyfin" {
                            Label(spotlight ? "Play" : "Resume", systemImage: "play.fill")
                        } else {
                            Label("Resume · \(entry.detail)", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    details
                }
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 640, alignment: .leading)
            .padding(28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("start.banner")
        .accessibilityValue(hovering || Self.testHover ? "moving" : "resting")
        .task(id: entry.id) { backdrops = await loadBackdrops() }
    }

    @ViewBuilder private var details: some View {
        switch entry.open {
        case .movie(let movie): NavigationLink("Details", value: movie).controlSize(.large)
        case .series(let series), .episode(_, let series): NavigationLink("Details", value: series).controlSize(.large)
        case .jellyfin(let item) where item.type != "Episode": NavigationLink("Details", value: item).controlSize(.large)
        default: EmptyView()
        }
    }

    /// IPTV_TESTHOVER=1 (debug): the backdrop moves without the pointer, for screenshots (pointer
    /// input cannot be injected in checks).
    static var testHover: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["IPTV_TESTHOVER"] == "1"
        #else
        false
        #endif
    }

    /// All of the title's backdrops (at most five), else its picture.
    private func loadBackdrops() async -> [URL] {
        var list: [String] = []
        switch entry.open {
        case .movie(let movie): list = (try? await app.client?.movieDetails(movie.id))?.backdrops ?? []
        case .series(let series), .episode(_, let series):
            list = (try? await app.client?.seriesInfo(series.id))?.backdrops ?? []
        case .jellyfin(let item): list = jellyfin.backdropURLs(item)
        case .recording: break
        }
        let urls = list.prefix(5).compactMap(URL.init(string:))
        // A recording's image is its channel logo, no backdrop.
        guard entry.source != .recording else { return urls }
        return urls.isEmpty ? entry.image.map { [$0] } ?? [] : urls
    }

    private var kind: String {
        switch entry.open {
        case .movie: String(localized: "MOVIE")
        case .series, .episode: String(localized: "SERIES")
        case .jellyfin(let item): item.type == "Episode" ? String(localized: "SERIES") : String(localized: "MOVIE")
        case .recording: String(localized: "RECORDING")
        }
    }

    /// "2019 · Comedy · ★ 7.9", as far as known.
    private var facts: String {
        var list: [String] = []
        switch entry.open {
        case .jellyfin(let item):
            if item.type == "Episode" { if let line = StartBuilder.episodeLine(item) { list.append(line) } } else {
                if let year = item.productionYear { list.append("\(year)") }
                if let genre = item.genres?.first { list.append(genre) }
                if let rating = item.communityRating { list.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
            }
        case .movie(let movie):
            if let rating = movie.rating, rating > 0 { list.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
        case .episode(let episode, _): list.append("\(episode.code) · \(episode.title)")
        default: break
        }
        return list.joined(separator: " · ")
    }
}

// MARK: - Cards

/// A wide card: still, title, detail and progress (Continue Watching, Next Up, recordings).
/// A recording's image is its channel's logo, shown whole on a logo tile instead of filling the card.
private struct StartWideCard: View {
    let entry: LibraryEntry
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .frame(width: 280, height: 158)
                .overlay {
                    if entry.source == .recording, let logo = entry.image {
                        LogoTile(url: logo.absoluteString, name: entry.detail, width: 280, fixedHeight: 158, cornerRadius: 10)
                    } else {
                        RemoteImage(url: entry.image?.absoluteString, maxPixel: 600) { Rectangle().fill(.quaternary) }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottom) {
                    if let progress = entry.progress, progress > 0 { ProgressBar(value: progress, height: 4).padding(10) }
                }
                .scaleEffect(hovering ? 1.03 : 1)
                .animation(.snappy(duration: 0.18), value: hovering)
            Text(verbatim: entry.title).font(.callout.weight(.medium)).lineLimit(1)
            if !entry.detail.isEmpty {
                Text(verbatim: entry.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 280, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// A channel of Jetzt live: logo, the show on now and its progress.
private struct StartLiveCard: View {
    let channel: LiveChannel
    @ObservedObject var guide: ChannelGuide

    var body: some View {
        // Redrawn every full minute, so the card moves on to the next show while Start stays open.
        TimelineView(LiveClock.everyMinute) { context in
            card(now: LiveClock.now(context.date))
        }
    }

    private func card(now: Date) -> some View {
        let show = guide.entries?.first { $0.start <= now && $0.end > now }
        return HStack(spacing: 12) {
            LogoTile(url: channel.icon, name: channel.displayName, width: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: channel.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(verbatim: show?.title ?? "–").font(.callout.weight(.medium)).lineLimit(1)
                if let show { ProgressBar(value: show.progress(at: now), height: 3).frame(maxWidth: 160) }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 300, height: 88)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        #if DEBUG
        .onChange(of: show?.id, initial: true) { _, _ in debugLog("[test] start live \(channel.id): \(show?.title ?? "–")") }
        #endif
    }
}

/// A show of Heute Abend: time, channel, title; a red dot once scheduled.
private struct StartShowCard: View {
    let item: TonightItem
    let scheduled: Bool

    var body: some View {
        HStack(spacing: 12) {
            LogoTile(url: item.channel.icon, name: item.channel.displayName, width: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.show.start, format: .dateTime.hour().minute()).font(.caption.weight(.semibold)).monospacedDigit()
                    Text(verbatim: item.channel.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if scheduled { Circle().fill(Theme.record).frame(width: 7, height: 7) }
                }
                Text(verbatim: item.show.title).font(.callout.weight(.medium)).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 300, height: 88)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}
