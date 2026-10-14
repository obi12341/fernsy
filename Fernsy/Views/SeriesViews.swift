import SwiftUI

private let posterColumns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20, alignment: .top)]

struct SeriesGridView: View {
    @EnvironmentObject private var app: AppModel
    let categoryID: String
    let query: String
    @AppStorage("library.seriesSort") private var sort: LibrarySort = .newest

    var body: some View {
        let list = app.filteredSeries(categoryID: categoryID, query: query, sort: sort)
        ScrollView {
            LazyVGrid(columns: posterColumns, spacing: 24) {
                ForEach(list) { show in
                    NavigationLink(value: show) {
                        PosterCard(title: show.name, imageURL: show.cover, rating: show.rating,
                                   isFavorite: app.isFavorite("series:\(show.id)"))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(app.isFavorite("series:\(show.id)") ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") {
                            app.toggleFavorite("series:\(show.id)")
                        }
                    }
                }
            }
            .padding(24)
        }
        .overlay {
            if list.isEmpty && !app.series.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .toolbar { SortMenu(sort: $sort) }
        .navigationTitle("Serien")
        .navigationSubtitle("\(list.count) Serien")
    }
}

struct SeriesDetailView: View {
    @EnvironmentObject private var app: AppModel
    let series: Series

    @State private var info: SeriesInfo?
    @State private var season: Int?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RemoteImage(url: info?.backdrop ?? series.cover, maxPixel: 1600) {
                    Rectangle().fill(.quaternary)
                }
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)], startPoint: .center, endPoint: .bottom))

                HStack(alignment: .top, spacing: 28) {
                    RemoteImage(url: series.cover, maxPixel: 500) { Rectangle().fill(.quaternary) }
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .frame(width: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 10)
                        .offset(y: -90)
                        .padding(.bottom, -90)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(series.name).font(.largeTitle.weight(.bold)).textSelection(.enabled)
                        HStack(spacing: 12) {
                            if let date = series.releaseDate { Text(String(date.prefix(4))) }
                            if let genre = series.genre { Text(genre).lineLimit(1) }
                            if let rating = series.rating { Label(String(format: "%.1f", rating), systemImage: "star.fill") }
                            Button {
                                app.toggleFavorite("series:\(series.id)")
                            } label: {
                                Image(systemName: app.isFavorite("series:\(series.id)") ? "star.fill" : "star")
                            }
                            .buttonStyle(.borderless)
                        }
                        .foregroundStyle(.secondary)
                        if let plot = series.plot {
                            Text(plot).foregroundStyle(.secondary).frame(maxWidth: 720, alignment: .leading).textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, 32)

                episodes
                    .padding(32)
            }
        }
        .navigationTitle(series.name)
        .task(id: series.id) {
            do {
                let loaded = try await app.client?.seriesInfo(series.id)
                info = loaded
                season = loaded?.seasons.keys.sorted().first
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var episodes: some View {
        if let info, let season {
            let seasons = info.seasons.keys.sorted()
            VStack(alignment: .leading, spacing: 16) {
                if seasons.count > 1 {
                    Picker("Staffel", selection: Binding(get: { season }, set: { self.season = $0 })) {
                        ForEach(seasons, id: \.self) { Text("Staffel \($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: min(CGFloat(seasons.count) * 110, 900))
                } else {
                    Text("Staffel \(season)").font(.title2.weight(.semibold))
                }
                LazyVStack(spacing: 10) {
                    ForEach(info.seasons[season] ?? []) { episode in
                        EpisodeRow(episode: episode, resume: app.resumePosition("episode.\(episode.id)")) {
                            app.play(episode, of: series)
                        }
                    }
                }
            }
        } else if let error {
            Text(error).foregroundStyle(.secondary)
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let resume: Double
    let play: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: play) {
            HStack(alignment: .top, spacing: 16) {
                RemoteImage(url: episode.image, maxPixel: 400) {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "play.rectangle").font(.title).foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 200, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if hovering {
                        Image(systemName: "play.circle.fill").font(.system(size: 40)).foregroundStyle(.white).shadow(radius: 6)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(episode.number). \(episode.title)").font(.headline).lineLimit(1)
                        Spacer()
                        if let d = episode.durationSeconds, d > 0 {
                            Text("\(d / 60) Min.").foregroundStyle(.secondary).font(.callout)
                        }
                    }
                    if let plot = episode.plot {
                        Text(plot).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                    }
                    if resume > 0 {
                        Label("Fortsetzen bei \(formatTime(resume))", systemImage: "play.circle")
                            .font(.caption).foregroundStyle(.tint)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct FavoritesView: View {
    @EnvironmentObject private var app: AppModel
    let kind: String
    let query: String

    var body: some View {
        let needle = makeSearchKey(query)
        let channels = (kind == allCategoryID || kind == "live")
            ? app.channels.filter { app.isFavorite("live:\($0.id)") && (needle.isEmpty || $0.searchKey.contains(needle)) } : []
        let movies = (kind == allCategoryID || kind == "movie")
            ? app.movies.filter { app.isFavorite("movie:\($0.id)") && (needle.isEmpty || $0.searchKey.contains(needle)) } : []
        let shows = (kind == allCategoryID || kind == "series")
            ? app.series.filter { app.isFavorite("series:\($0.id)") && (needle.isEmpty || $0.searchKey.contains(needle)) } : []

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !channels.isEmpty {
                    Text("Sender").font(.title2.weight(.semibold))
                    VStack(spacing: 2) {
                        ForEach(channels) { channel in
                            Button { app.play(channel) } label: {
                                ChannelRow(channel: channel, isPlaying: false)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !movies.isEmpty {
                    Text("Filme").font(.title2.weight(.semibold))
                    LazyVGrid(columns: posterColumns, spacing: 24) {
                        ForEach(movies) { movie in
                            NavigationLink(value: movie) {
                                PosterCard(title: movie.name, imageURL: movie.poster, rating: movie.rating, isFavorite: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !shows.isEmpty {
                    Text("Serien").font(.title2.weight(.semibold))
                    LazyVGrid(columns: posterColumns, spacing: 24) {
                        ForEach(shows) { show in
                            NavigationLink(value: show) {
                                PosterCard(title: show.name, imageURL: show.cover, rating: show.rating, isFavorite: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if channels.isEmpty && movies.isEmpty && shows.isEmpty {
                ContentUnavailableView("Noch keine Favoriten", systemImage: "star",
                                       description: Text("Markiere Sender, Filme oder Serien mit dem Stern."))
            }
        }
        .navigationTitle("Favoriten")
    }
}
