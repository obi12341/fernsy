import FernsyCore
import FernsyPlayer
import SwiftUI

/// Start (ios-app "Start"): the newest item to continue (or the newest film) as a large entry,
/// then On Now, Continue Watching, Next Up, Tonight, Recently Added, the largest categories and
/// genres and Best Rated; each row only with entries. No recordings row on iOS.
struct StartView: View {
    @EnvironmentObject private var model: TVModel
    @State private var path: [DetailTarget] = []
    @State private var rows = StartRows()
    @State private var asked: (show: EPGEntry, channel: LiveChannel)?
    @State private var showsSettings = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        // Everything shown comes from `rows`, built when its inputs change (tvos-start-scrolling).
        let resume = rows.resume
        let added = rows.added
        let hero = resume.first ?? rows.spotlight
        let live = rows.live
        let tonight = rows.tonight
        NavigationStack(path: $path) {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if let hero {
                    Hero(entry: hero, spotlight: resume.isEmpty) { open(hero) } info: { info(hero) }
                }
                if !live.channels.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        RowTitle(title: "On Now", note: live.source == .favorites ? "Favorites" : live.source == .recent ? "Recently Watched" : nil)
                        CardRow {
                            ForEach(live.channels) { channel in
                                Button {
                                    model.zapSource = live.source
                                    Task { await model.zap(to: channel) }
                                } label: {
                                    LiveCard(channel: channel, guide: model.guide.guide(channel.id))
                                }
                                .buttonStyle(.plain)
                                .contextMenu { ChannelActions(channel: channel) }
                                .accessibilityIdentifier("start.live.\(channel.id)")
                            }
                        }
                    }
                }
                wideRow("Continue Watching", note: nil, id: "resume", resume)
                wideRow("Next Up", note: "Jellyfin", id: "next", rows.nextUp)
                if !tonight.shows.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        RowTitle(title: LocalizedStringKey(tonight.title))
                        CardRow {
                            ForEach(tonight.shows, id: \.channel.id) { item in
                                Button { pick(item.show, on: item.channel) } label: {
                                    ShowCard(show: item.show, channel: item.channel)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("start.tonight.\(item.channel.id)")
                            }
                        }
                    }
                }
                if !added.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        RowTitle(title: "Recently Added", note: "IPTV and Jellyfin")
                        CardRow {
                            ForEach(added) { entry in
                                Button { info(entry) } label: {
                                    PosterCard(title: entry.title, image: entry.image, badge: Self.sourceName(entry.source),
                                               badgeColor: entry.source == .jellyfin ? Color(hex: 0x6C65F0) : Color(hex: 0x0F0E12, opacity: 0.65))
                                        .frame(width: 120)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("start.added.\(entry.id)")
                            }
                        }
                    }
                }
                ForEach(rows.categories) { row in posterRow(row.title, id: row.id, row.entries) }
                posterRow(String(localized: "Best Rated"), id: "best", rows.bestRated)
                if resume.isEmpty && added.isEmpty && live.channels.isEmpty {
                    Text("Your movies and series appear here once the library has loaded.")
                        .foregroundStyle(TVTheme.secondary).padding(16)
                }
            }
            .padding(.bottom, 30)
        }
        .ignoresSafeArea(edges: hero != nil ? .top : [])
        .background(TVTheme.background.ignoresSafeArea())
        .navigationDestination(for: DetailTarget.self) { DetailPage(target: $0) }
        .navigationDestination(isPresented: $showsSettings) { SettingsView() }
        .toolbar {
            // On iPhone Settings has no tab (five tabs at most): the gear opens it from Start.
            if sizeClass == .compact {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(Text("Settings"))
                        .accessibilityIdentifier("start.settings")
                }
            }
        }
        .task(id: model.jellyfin.session?.userId) { if model.jellyfin.session != nil { await model.jellyfin.refreshHome() } }
        // Rows from the catalog once per change of it, not per redraw.
        .task(id: "\(model.movies.count).\(model.series.count).\(model.jellyfin.films.count).\(model.jellyfin.latestFilms.count)") {
            let catalog = model.startRows()
            rows.spotlight = catalog.spotlight
            rows.categories = catalog.categories
            rows.bestRated = catalog.bestRated
            rows.added = catalog.added
            refreshResume()
            if case .movie(let movie)? = rows.spotlight?.open { _ = await model.movieDetails(movie) }
        }
        .onAppear { refreshResume(); refreshLive() }
        .onChange(of: resumeInputs) { refreshResume() }
        .onChange(of: liveInputs) { refreshLive() }
        .task(id: live.channels.map(\.id)) {
            for channel in live.channels { await model.loadGuide(for: channel) }
            rows.tonight = model.tonight(on: rows.live.channels)
        }
        .sheet(isPresented: Binding(get: { asked != nil }, set: { if !$0 { asked = nil } })) {
            if let asked { ShowDetailSheet(show: asked.show, channel: asked.channel) }
        }
        }
    }

    private var resumeInputs: String {
        let playing = model.playingVOD != nil
        let jellyfin = (model.jellyfin.resume + model.jellyfin.nextUp).map(\.id).joined(separator: ",")
        return "\(playing)|\(model.resumeRevision)|\(jellyfin)"
    }

    private var liveInputs: String {
        "\(model.favorites.sorted())|\(model.recentChannels).\(model.channels.count).\(model.visibility.modifiedAt.timeIntervalSince1970)"
    }

    private func refreshResume() {
        rows.resume = model.continueWatching
        rows.nextUp = model.nextUpEntries
    }

    private func refreshLive() {
        rows.live = model.startChannels
        rows.tonight = model.tonight(on: rows.live.channels)
    }

    /// A running show plays its channel; a later one shows its details (no recording on iOS).
    private func pick(_ show: EPGEntry, on channel: LiveChannel) {
        if show.start <= Date() {
            model.zapSource = rows.live.source
            Task { await model.zap(to: channel) }
        } else {
            asked = (show, channel)
        }
    }

    @ViewBuilder private func posterRow(_ title: String, id: String, _ entries: [LibraryEntry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                RowTitle(title: LocalizedStringKey(title))
                CardRow {
                    ForEach(entries) { entry in
                        Button { info(entry) } label: {
                            PosterCard(title: entry.title, image: entry.image,
                                       rating: { if case .movie(let movie) = entry.open { movie.rating } else { nil } }(),
                                       badge: entry.source == .jellyfin ? "Jellyfin" : nil)
                                .frame(width: 120)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("start.\(id).\(entry.id)")
                    }
                }
            }
        }
    }

    @ViewBuilder private func wideRow(_ title: LocalizedStringKey, note: LocalizedStringKey?, id: String, _ entries: [LibraryEntry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                RowTitle(title: title, note: note)
                CardRow {
                    ForEach(entries) { entry in
                        Button { open(entry) } label: {
                            WideCard(title: entry.title, detail: entry.detail, image: entry.image,
                                     source: Self.sourceName(entry.source), progress: entry.progress)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { if DetailTarget.of(entry.open) != nil { Button("Details", systemImage: "info.circle") { info(entry) } } }
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

    /// A tap resumes; films and series without a position open their page.
    private func open(_ entry: LibraryEntry) {
        switch entry.open {
        case .movie(let movie): model.play(.movie(movie))
        case .episode(let episode, let series): model.play(.episode(episode, series))
        case .jellyfin(let item): model.play(.jellyfin(item))
        case .series: info(entry)
        case .recording: break
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

/// The large entry: backdrop, kind, title, facts, Resume (or Play) and info.
private struct Hero: View {
    @EnvironmentObject private var model: TVModel
    let entry: LibraryEntry
    var spotlight = false
    let resume: () -> Void
    let info: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Full width: 4:3 on iPhone; on iPad a fixed height, since 4:3 of the iPad's width
            // would fill the screen (and a height cap with 4:3 left the right side empty).
            Color.clear
                .aspectRatio(sizeClass == .regular ? nil : 4 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(height: sizeClass == .regular ? 560 : nil)
                .overlay { RemoteImage(url: backdrop, maxPixel: 1400) { ArtPlaceholder(seed: entry.title) } }
                .clipped()
                .overlay {
                    LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: TVTheme.background, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
            VStack(alignment: .leading, spacing: 8) {
                Text(spotlight ? "NEW · \(kind)" : "CONTINUE WATCHING · \(kind)").font(.caption.weight(.bold)).tracking(1.2).opacity(0.8)
                Text(verbatim: entry.title).font(.largeTitle.bold()).lineLimit(2).minimumScaleFactor(0.6)
                HStack(spacing: 10) {
                    Button(action: resume) {
                        if spotlight {
                            Label("Play", systemImage: "play.fill")
                        } else {
                            Label(entry.detail.isEmpty ? String(localized: "Resume") : String(localized: "Resume · \(entry.detail)"), systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(ActionButtonStyle())
                    .accessibilityIdentifier("start.hero.resume")
                    if DetailTarget.of(entry.open) != nil {
                        Button(action: info) { Image(systemName: "info.circle") }
                            .buttonStyle(ActionButtonStyle(prominent: false))
                            .accessibilityIdentifier("start.hero.info")
                    }
                }
                .padding(.top, 6)
            }
            .padding(16)
        }
    }

    private var backdrop: URL? {
        let list: [String] = switch entry.open {
        case .movie(let movie): model.movieInfo[movie.id]?.backdrops ?? []
        case .series(let series), .episode(_, let series): model.seriesInfo[series.id]?.backdrops ?? []
        case .jellyfin(let item): model.jellyfin.backdropURLs(item)
        case .recording: []
        }
        return list.first.flatMap(URL.init(string:)) ?? entry.image
    }

    private var kind: String {
        switch entry.open {
        case .movie: String(localized: "MOVIE")
        case .series, .episode: String(localized: "SERIES")
        case .jellyfin(let item): item.type == "Episode" ? String(localized: "SERIES") : String(localized: "MOVIE")
        case .recording: String(localized: "RECORDING")
        }
    }
}

/// A live channel on Start: logo, the show on now with its progress and time left.
private struct LiveCard: View {
    @EnvironmentObject private var model: TVModel
    let channel: LiveChannel
    @ObservedObject var guide: ChannelGuide

    var body: some View {
        let show = model.currentShow(on: channel)
        HStack(spacing: 10) {
            ChannelLogo(channel: channel).frame(width: 64, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: channel.displayName).font(.caption).foregroundStyle(TVTheme.secondary).lineLimit(1)
                Text(verbatim: show?.title ?? String(localized: "No program information")).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let show { ShowProgress(show: show).frame(width: 90, height: 3) }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 250, height: 74, alignment: .leading)
        .background(TVTheme.tile, in: .rect(cornerRadius: 14))
        .contentShape(.rect)
    }
}

/// A show of tonight on Start: time, channel and title.
private struct ShowCard: View {
    let show: EPGEntry
    let channel: LiveChannel

    var body: some View {
        HStack(spacing: 10) {
            ChannelLogo(channel: channel).frame(width: 56, height: 35)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(show.start, format: .dateTime.hour().minute()).font(.caption.weight(.bold).monospacedDigit())
                    Text(verbatim: channel.displayName).font(.caption).foregroundStyle(TVTheme.tertiary).lineLimit(1)
                }
                Text(verbatim: show.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 250, height: 74, alignment: .leading)
        .background(TVTheme.tile, in: .rect(cornerRadius: 14))
        .contentShape(.rect)
    }
}

/// A show's details (a later show in the guide, Tonight or the search): title, time, channel and
/// description, and "Watch Channel" (no recording on iPhone and iPad).
struct ShowDetailSheet: View {
    @EnvironmentObject private var model: TVModel
    @Environment(\.dismiss) private var dismiss
    let show: EPGEntry
    let channel: LiveChannel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ChannelLogo(channel: channel).frame(width: 64, height: 40)
                        Text(verbatim: channel.displayName).font(.headline)
                    }
                    Text(verbatim: show.title).font(.title2.bold())
                    Text(verbatim: show.start.formatted(.dateTime.weekday(.wide).day().month().hour().minute()) + " – "
                         + show.end.formatted(.dateTime.hour().minute()))
                        .foregroundStyle(TVTheme.secondary)
                    if !show.description.isEmpty {
                        Text(verbatim: show.description).foregroundStyle(TVTheme.secondary)
                    }
                    Button {
                        dismiss()
                        Task { await model.zap(to: channel) }
                    } label: {
                        Label("Watch Channel", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActionButtonStyle())
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}
