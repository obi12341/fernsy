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

    /// For the segmented control.
    var shortTitle: String {
        switch self {
        case .newest: return String(localized: "Neueste")
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
                                   progress: resumeFraction(movie),
                                   fraction: app.resumeFraction("movie.\(movie.id)"))
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
                ForEach(LibrarySort.allCases) { Text($0.shortTitle).tag($0) }
            }
            .pickerStyle(.segmented)
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
                DetailBackdrop(url: details?.backdrop ?? movie.poster)

                HStack(alignment: .top, spacing: 28) {
                    RemoteImage(url: details?.poster ?? movie.poster, maxPixel: 500) {
                        Rectangle().fill(.quaternary)
                    }
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(width: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                    .offset(y: -120)
                    .padding(.bottom, -120)

                    VStack(alignment: .leading, spacing: 14) {
                        Text(verbatim: movie.name).font(.largeTitle.weight(.bold)).textSelection(.enabled)
                        metaLine
                        actionButtons
                        if let plot = details?.plot {
                            Text(verbatim: plot).font(.body).foregroundStyle(.secondary).textSelection(.enabled)
                                .lineSpacing(3)
                                .frame(maxWidth: 680, alignment: .leading)
                        }
                        detailsGrid.padding(.top, 6)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 36)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle(movie.name)
        .task(id: movie.id) {
            details = try? await app.client?.movieDetails(movie.id)
        }
    }

    private var metaLine: some View {
        HStack(spacing: 8) {
            let parts = [details?.releaseDate.map { String($0.prefix(4)) }, runtimeText(details?.duration), details?.genre].compactMap { $0 }
            Text(verbatim: parts.joined(separator: " · ")).lineLimit(1)
            if let rating = details?.rating ?? movie.rating, rating > 0 {
                Text(verbatim: "· ★ \(rating.formatted(.number.precision(.fractionLength(1))))")
            }
        }
        .foregroundStyle(.secondary)
    }

    private var actionButtons: some View {
        let key = "movie.\(movie.id)"
        let resume = app.resumePosition(key)
        let fraction = app.resumeFraction(key)
        return HStack(spacing: 12) {
            Button {
                app.play(movie)
            } label: {
                if resume > 0 {
                    HStack(spacing: 8) {
                        Label("Fortsetzen", systemImage: "play.fill")
                        Text(verbatim: resumeDetail(resume, fraction: fraction)).opacity(0.8)
                    }
                    .padding(.horizontal, 8)
                } else {
                    Label("Abspielen", systemImage: "play.fill").padding(.horizontal, 8)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if resume > 0 {
                Button("Von vorne") {
                    app.saveResume(key, position: 0, duration: 0)
                    app.play(movie)
                }
                .controlSize(.large)
            }

            Button {
                app.toggleFavorite("movie:\(movie.id)")
            } label: {
                Image(systemName: app.isFavorite("movie:\(movie.id)") ? "star.fill" : "star")
                    .foregroundStyle(app.isFavorite("movie:\(movie.id)") ? .yellow : .primary)
            }
            .controlSize(.large)
            .help("Favorit")
        }
    }

    /// "1:12:40 · noch 51 Min." when the length is known.
    private func resumeDetail(_ position: Double, fraction: Double?) -> String {
        guard let fraction, fraction > 0 else { return formatTime(position) }
        let remaining = Int(position / fraction - position) / 60
        return String(localized: "\(formatTime(position)) · noch \(remaining) Min.")
    }

    private var detailsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            if let director = details?.director, !director.isEmpty { row("Regie", director) }
            if let cast = details?.cast, !cast.isEmpty { row("Besetzung", cast) }
            if let genre = details?.genre, !genre.isEmpty { row("Genre", genre) }
            row("Format", movie.containerExtension.uppercased())
        }
        .font(.callout)
        .frame(maxWidth: 680, alignment: .leading)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.tertiary).gridColumnAlignment(.leading)
            Text(verbatim: value).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
        }
    }
}

/// The backdrop of a detail page: under the transparent toolbar, fading into the window.
struct DetailBackdrop: View {
    let url: String?

    var body: some View {
        RemoteImage(url: url, maxPixel: 1600) {
            Rectangle().fill(.quaternary)
        }
        .frame(height: 380)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor).opacity(0.6), Color(nsColor: .windowBackgroundColor)],
                                startPoint: .init(x: 0.5, y: 0.35), endPoint: .bottom))
    }
}

/// "02:04:00", "124 min" or "124" → "2 Std. 4 Min."; nil when it cannot be read.
func runtimeText(_ raw: String?) -> String? {
    guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
    var minutes: Int?
    let parts = raw.split(separator: ":").compactMap { Int($0) }
    if parts.count == 3 { minutes = parts[0] * 60 + parts[1] }
    else if parts.count == 2 { minutes = parts[0] * 60 + parts[1] }
    else if let number = Int(raw.prefix { $0.isNumber }) { minutes = number }
    guard let minutes, minutes > 0 else { return nil }
    if minutes < 60 { return String(localized: "\(minutes) Min.") }
    return minutes % 60 == 0 ? String(localized: "\(minutes / 60) Std.") : String(localized: "\(minutes / 60) Std. \(minutes % 60) Min.")
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let s = Int(seconds)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}
