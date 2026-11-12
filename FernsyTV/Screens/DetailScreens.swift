import FernsyCore
import FernsyPlayer
import SwiftUI

/// A film page (design screen `film`) for an IPTV film or a Jellyfin film: backdrop, facts,
/// description, Resume (or Play), From the Beginning, favourite, and director, cast and tracks.
struct FilmScreen: View {
    typealias Film = LibraryDetail.Film

    @EnvironmentObject private var model: TVModel
    let film: Film
    @State private var details: MovieDetails?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RemoteImage(url: backdrop, maxPixel: 1920) { ArtPlaceholder(seed: title) }
                .frame(width: 1920, height: 1080).clipped().ignoresSafeArea()
                .overlay {
                    LinearGradient(stops: [.init(color: TVTheme.background, location: 0), .init(color: TVTheme.background.opacity(0.6), location: 0.45),
                                           .init(color: .clear, location: 0.8)], startPoint: .leading, endPoint: .trailing).ignoresSafeArea()
                    LinearGradient(colors: [TVTheme.background, .clear], startPoint: .bottom, endPoint: .center).ignoresSafeArea()
                }
            VStack(alignment: .leading, spacing: 22) {
                Spacer().frame(height: 200)
                Text(verbatim: title).font(.system(size: 96, weight: .bold)).lineLimit(2).minimumScaleFactor(0.6)
                HStack(spacing: 14) {
                    Text(verbatim: facts.joined(separator: "  ·  "))
                    ForEach(badges, id: \.self) { badge in
                        Text(verbatim: badge).font(.system(size: 17, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
                    }
                }
                .font(.system(size: 25)).foregroundStyle(TVTheme.text.opacity(0.8))
                if let overview, !overview.isEmpty {
                    Text(verbatim: overview).font(.system(size: 26)).lineSpacing(8).lineLimit(4)
                        .foregroundStyle(TVTheme.text.opacity(0.82)).frame(maxWidth: 880, alignment: .leading)
                }
                HStack(spacing: 22) {
                    Button { play(fromStart: false) } label: {
                        Label(position > 0 ? "Resume · \(Duration.seconds(position).formatted(.time(pattern: .hourMinuteSecond)))" : "Play",
                              systemImage: "play.fill")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .accessibilityIdentifier("film.play")
                    if position > 0 {
                        Button { play(fromStart: true) } label: { Text("From the Beginning") }
                            .buttonStyle(ActionButtonStyle())
                            .accessibilityIdentifier("film.fromStart")
                    }
                    Button { toggleFavorite() } label: { FavoriteStar(isFavorite: isFavorite) }
                    .buttonStyle(ActionButtonStyle(round: true))
                    .accessibilityIdentifier("film.favorite")
                    .accessibilityValue(isFavorite ? "favorite" : "")
                }
                .padding(.top, 20)
                .focusSection()
                if let fraction = progress, fraction > 0 {
                    HStack(spacing: 16) {
                        ProgressBar(value: fraction).frame(width: 260)
                        if duration > 0 { Text(String(localized: "\(Int(((duration - position) / 60).rounded())) min left")) }
                    }
                    .font(.system(size: 21)).foregroundStyle(TVTheme.text.opacity(0.6))
                }
                Spacer()
                factsGrid
            }
            .padding(.horizontal, 90)
            .padding(.bottom, 64)
        }
        .foregroundStyle(TVTheme.text)
        .toolbar(.hidden, for: .tabBar)
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

    private var facts: [String] { LibraryDetail.facts(film, jellyfin: jfItem, details: details) }

    private var badges: [String] {
        guard let item = jfItem else { return [] }
        var list: [String] = []
        if let rating = item.officialRating { list.append(rating) }
        return list
    }

    private var position: Double { LibraryDetail.position(film, jellyfin: jfItem, model: model) }

    private var duration: Double { LibraryDetail.duration(film, jellyfin: jfItem, model: model) }

    private var progress: Double? { duration > 0 ? position / duration : nil }

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

    @ViewBuilder private var factsGrid: some View {
        let entries = factEntries
        if !entries.isEmpty {
            HStack(alignment: .top, spacing: 40) {
                ForEach(entries.indices, id: \.self) { index in
                    let (key, value) = entries[index]
                    VStack(alignment: .leading, spacing: 8) {
                        Text(key).font(.system(size: 19, weight: .bold)).tracking(1.3).foregroundStyle(TVTheme.text.opacity(0.5))
                        Text(verbatim: value).font(.system(size: 23)).lineSpacing(4).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 30)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
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

/// A series page (design screen `serie`) for an IPTV or Jellyfin series: source, seasons, "Next
/// Episode", favourite, a season picker and the season's episodes.
struct SeriesScreen: View {
    enum Show { case iptv(Series), jellyfin(JFItem) }

    @EnvironmentObject private var model: TVModel
    let show: Show
    @State private var info: SeriesInfo?
    @State private var season: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RemoteImage(url: backdrop, maxPixel: 1920) { ArtPlaceholder(seed: title) }
                .frame(width: 1920, height: 1080).clipped().ignoresSafeArea()
                .overlay {
                    LinearGradient(stops: [.init(color: TVTheme.background, location: 0), .init(color: TVTheme.background.opacity(0.6), location: 0.45),
                                           .init(color: .clear, location: 0.8)], startPoint: .leading, endPoint: .trailing).ignoresSafeArea()
                    LinearGradient(colors: [TVTheme.background, TVTheme.background.opacity(0.7), .clear], startPoint: .bottom, endPoint: .center).ignoresSafeArea()
                }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Spacer().frame(height: 130)
                    HStack(spacing: 14) {
                        Tag(text: Text(verbatim: sourceName), background: TVTheme.accentLight.opacity(0.3), foreground: Color(hex: 0xDAD8FF))
                        Text(seasonKeys.count == 1 ? "Series · 1 season" : "Series · \(seasonKeys.count) seasons")
                            .font(.system(size: 24)).foregroundStyle(TVTheme.text.opacity(0.75))
                    }
                    Text(verbatim: title).font(.system(size: 88, weight: .bold)).lineLimit(2).minimumScaleFactor(0.6)
                    if let overview, !overview.isEmpty {
                        Text(verbatim: overview).font(.system(size: 25)).lineSpacing(8).lineLimit(3)
                            .foregroundStyle(TVTheme.text.opacity(0.82)).frame(maxWidth: 860, alignment: .leading)
                    }
                    HStack(spacing: 22) {
                        if let next = nextEpisode {
                            Button { play(next) } label: { Label("Next Episode · \(next.label)", systemImage: "play.fill") }
                                .buttonStyle(ActionButtonStyle())
                                .accessibilityIdentifier("series.next")
                        }
                        Button { toggleFavorite() } label: { FavoriteStar(isFavorite: isFavorite) }
                        .buttonStyle(ActionButtonStyle(round: true))
                        .accessibilityIdentifier("series.favorite")
                        .accessibilityValue(isFavorite ? "favorite" : "")
                    }
                    .padding(.top, 14)
                    .focusSection()
                    HStack(spacing: 10) {
                        ForEach(seasonKeys, id: \.self) { key in
                            Button { season = key } label: {
                                Text(seasonTitle(key)).font(.system(size: 24, weight: .semibold)).padding(.horizontal, 26).frame(height: 54)
                            }
                            .buttonStyle(SeasonStyle(selected: currentSeason == key))
                            .accessibilityIdentifier("season.\(key)")
                        }
                    }
                    .padding(.top, 40)
                    .focusSection()
                    CardRow {
                        ForEach(episodes) { episode in
                            Button { play(episode) } label: {
                                WideCard(title: episode.title, detail: episode.number, image: episode.image, progress: episode.progress,
                                         topRight: episode.watched ? AnyView(Image(systemName: "checkmark").font(.system(size: 20, weight: .heavy))
                                             .frame(width: 36, height: 36).background(Color(hex: 0x6C65F0), in: .circle)) : nil,
                                         topLeft: episode.id == nextEpisode?.id ? AnyView(Tag(text: Text("Up Next"), background: .white, foreground: TVTheme.focusedText)) : nil)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("episode.\(episode.id)")
                            .accessibilityValue(episode.id == nextEpisode?.id ? "next" : episode.watched ? "watched" : "")
                        }
                    }
                }
                .padding(.horizontal, 90)
                .padding(.bottom, 60)
            }
        }
        .foregroundStyle(TVTheme.text)
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
        .onChange(of: season) { _, value in
            if case .jellyfin(let item) = show, let value { Task { await model.jellyfin.loadEpisodes(seriesId: item.id, seasonId: value) } }
        }
    }

    /// One episode, whichever the source.
    typealias EpisodeEntry = LibraryDetail.EpisodeEntry

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
            return (info?.seasons[key] ?? []).map { LibraryDetail.entry($0, series, model) }
        case .jellyfin:
            guard let key = currentSeason else { return [] }
            return (model.jellyfin.episodes[key] ?? []).map(LibraryDetail.entry)
        }
    }


    /// The episode to continue with: Jellyfin's Next Up, or the IPTV rule (TVModel.nextEpisode).
    private var nextEpisode: EpisodeEntry? {
        switch show {
        case .iptv(let series):
            guard let info, let episode = model.nextEpisode(of: series, in: info) else { return nil }
            return LibraryDetail.entry(episode, series, model)
        case .jellyfin(let item):
            if let next = model.jellyfin.nextUp.first(where: { $0.seriesId == item.id }) { return LibraryDetail.entry(next) }
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

    private func play(_ episode: EpisodeEntry) { model.play(episode.item) }
}

/// The star of a favourite button: gold for a favourite, and in the button's own color while
/// the button has focus. On the focused button's white pill neither gold nor the light text
/// color shows; there the filled star alone says that it is a favourite.
private struct FavoriteStar: View {
    let isFavorite: Bool
    @Environment(\.isFocused) private var focused

    var body: some View {
        let star = Image(systemName: isFavorite ? "star.fill" : "star")
        if isFavorite && !focused {
            star.foregroundStyle(Color(hex: 0xFFC940))
        } else {
            star
        }
    }
}

private struct SeasonStyle: ButtonStyle {
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
