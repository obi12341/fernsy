import SwiftUI

enum LibrarySort: String, CaseIterable, Identifiable {
    case newest, name, rating
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: return String(localized: "Neueste zuerst")
        case .name: return String(localized: "Name")
        case .rating: return String(localized: "Bewertung")
        }
    }
}

extension AppModel {
    func filteredMovies(categoryID: String, sort: LibrarySort) -> [Movie] {
        let hidden = hiddenCategoryIDs(movieCategories)
        var list = categoryID == allCategoryID ? movies : (moviesByCategory[categoryID] ?? [])
        if !showAdult { list = list.filter { !$0.isAdult && !hidden.contains($0.categoryId ?? "") } }
        switch sort {
        case .newest: list.sort { $0.added > $1.added }
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .rating: list.sort { ($0.rating ?? 0) > ($1.rating ?? 0) }
        }
        return list
    }

    func filteredSeries(categoryID: String, sort: LibrarySort) -> [Series] {
        let hidden = hiddenCategoryIDs(seriesCategories)
        var list = categoryID == allCategoryID ? series : (seriesByCategory[categoryID] ?? [])
        if !showAdult { list = list.filter { !hidden.contains($0.categoryId ?? "") } }
        switch sort {
        case .newest: list.sort { $0.lastModified > $1.lastModified }
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .rating: list.sort { ($0.rating ?? 0) > ($1.rating ?? 0) }
        }
        return list
    }
}

private let posterColumns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20, alignment: .top)]

struct MovieGridView: View {
    @EnvironmentObject private var app: AppModel
    let categoryID: String
    @AppStorage("library.movieSort") private var sort: LibrarySort = .newest

    var body: some View {
        let movies = app.filteredMovies(categoryID: categoryID, sort: sort)
        ScrollView {
            LazyVGrid(columns: posterColumns, spacing: 24) {
                ForEach(movies) { movie in
                    NavigationLink(value: movie) {
                        PosterCard(title: movie.name, imageURL: movie.poster, rating: movie.rating,
                                   isFavorite: app.isFavorite("movie:\(movie.id)"),
                                   progress: resumeFraction(movie))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Abspielen") { app.play(movie) }
                        Button(app.isFavorite("movie:\(movie.id)") ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen") {
                            app.toggleFavorite("movie:\(movie.id)")
                        }
                    }
                }
            }
            .padding(24)
        }
        .toolbar { SortMenu(sort: $sort) }
        .navigationTitle("Filme")
        .navigationSubtitle("\(movies.count) Titel")
    }

    private func resumeFraction(_ movie: Movie) -> Double? {
        let pos = app.resumePosition("movie.\(movie.id)")
        return pos > 0 ? pos : nil
    }
}

struct SortMenu: ToolbarContent {
    @Binding var sort: LibrarySort

    var body: some ToolbarContent {
        ToolbarItem {
            Picker("Sortierung", selection: $sort) {
                ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .help("Sortierung")
        }
    }
}

struct PosterCard: View {
    let title: String
    let imageURL: String?
    let rating: Double?
    var isFavorite = false
    /// Seconds watched (shown as a "resume" badge).
    var progress: Double?
    /// Below the title, e.g. the year.
    var subtitle: String? = nil
    /// Watched completely (check mark).
    var watched = false
    /// 0…1 when partly watched (progress bar).
    var fraction: Double? = nil
    /// Series: episodes not watched yet.
    var unwatchedCount: Int? = nil

    @State private var hovering = false

    /// IPTV_TESTNOPOSTER=1 (DEBUG): every card shows its placeholder.
    #if DEBUG
    private static let showsPosters = ProcessInfo.processInfo.environment["IPTV_TESTNOPOSTER"] == nil
    #else
    private static let showsPosters = true
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A fixed 2:3 frame decides the size; artwork of other proportions fills it and is
            // clipped, instead of growing the card (and spilling over its neighbours).
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    RemoteImage(url: Self.showsPosters ? imageURL : nil, maxPixel: 420) {
                        // No or broken poster: the title on a neutral surface keeps the grid calm.
                        ZStack {
                            Rectangle().fill(.quaternary)
                            Text(title)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .lineLimit(4)
                                .foregroundStyle(.secondary)
                                .padding(12)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .padding(6)
                        .background(.black.opacity(0.5), in: Circle())
                        .padding(6)
                }
            }
            .overlay(alignment: .topLeading) {
                if (unwatchedCount ?? 0) == 0, let rating, rating > 0 {
                    Text(verbatim: "★ \(rating.formatted(.number.precision(.fractionLength(1))))")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .overlay(alignment: .topLeading) {
                if let unwatchedCount, unwatchedCount > 0 {
                    Text("\(unwatchedCount)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                } else if watched {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.title3)
                        .padding(6)
                        .accessibilityLabel("Gesehen")
                }
            }
            .overlay(alignment: .bottom) {
                if let fraction {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.black.opacity(0.55))
                            Rectangle().fill(Color.accentColor).frame(width: geo.size.width * fraction)
                        }
                    }
                    .frame(height: 4)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if progress != nil {
                    Label("Fortsetzen", systemImage: "play.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .shadow(color: .black.opacity(hovering ? 0.35 : 0.15), radius: hovering ? 12 : 4, y: hovering ? 6 : 2)
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.snappy(duration: 0.18), value: hovering)

            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct MovieDetailView: View {
    @EnvironmentObject private var app: AppModel
    let movie: Movie
    @State private var details: MovieDetails?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: details?.backdrop ?? movie.poster, maxPixel: 1600) {
                        Rectangle().fill(.quaternary)
                    }
                    .frame(height: 340)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)], startPoint: .center, endPoint: .bottom))
                }

                HStack(alignment: .top, spacing: 28) {
                    RemoteImage(url: details?.poster ?? movie.poster, maxPixel: 500) {
                        Rectangle().fill(.quaternary)
                    }
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(width: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 10)
                    .offset(y: -100)
                    .padding(.bottom, -100)

                    VStack(alignment: .leading, spacing: 14) {
                        Text(movie.name).font(.largeTitle.weight(.bold)).textSelection(.enabled)
                        metaLine
                        actionButtons
                        if let plot = details?.plot {
                            Text(plot).font(.body).foregroundStyle(.secondary).textSelection(.enabled)
                                .frame(maxWidth: 720, alignment: .leading)
                        }
                        if let cast = details?.cast {
                            LabeledContent("Besetzung") { Text(cast).foregroundStyle(.secondary) }
                        }
                        if let director = details?.director {
                            LabeledContent("Regie") { Text(director).foregroundStyle(.secondary) }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(movie.name)
        .task(id: movie.id) {
            details = try? await app.client?.movieDetails(movie.id)
        }
    }

    private var metaLine: some View {
        HStack(spacing: 12) {
            if let date = details?.releaseDate { Text(String(date.prefix(4))) }
            if let duration = details?.duration { Text(duration) }
            if let genre = details?.genre { Text(genre).lineLimit(1) }
            if let rating = details?.rating ?? movie.rating {
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
            }
            Text(movie.containerExtension.uppercased())
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary))
        }
        .foregroundStyle(.secondary)
    }

    private var actionButtons: some View {
        let resume = app.resumePosition("movie.\(movie.id)")
        return HStack(spacing: 12) {
            Button {
                app.play(movie)
            } label: {
                Label(resume > 0 ? "Fortsetzen (\(formatTime(resume)))" : "Abspielen", systemImage: "play.fill")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if resume > 0 {
                Button("Von vorne") {
                    app.saveResume("movie.\(movie.id)", position: 0, duration: 0)
                    app.play(movie)
                }
                .controlSize(.large)
            }

            Button {
                app.toggleFavorite("movie:\(movie.id)")
            } label: {
                Image(systemName: app.isFavorite("movie:\(movie.id)") ? "star.fill" : "star")
            }
            .controlSize(.large)
            .help("Favorit")
        }
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let s = Int(seconds)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}
