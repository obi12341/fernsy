import SwiftUI

/// Pseudo category id for "everything in this section".
let allCategoryID = "__all"

enum LiveMode: String {
    case list, guide
}

struct LibraryView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.openWindow) private var openWindow

    @State private var section: LibrarySection = .live
    @State private var categoryBySection: [LibrarySection: String] = [:]
    @State private var categoryFilter = ""
    @State private var query = ""
    @State private var path = NavigationPath()
    @AppStorage("liveMode") private var liveMode = LiveMode.list
    /// Edit mode of Live TV: hidden categories and channels are listed to show them again.
    @State private var editingLive = false

    private var categoryID: Binding<String?> {
        Binding(
            get: { categoryBySection[section] ?? allCategoryID },
            set: { categoryBySection[section] = $0 ?? allCategoryID; path = NavigationPath() }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { section }, set: { if let s = $0 { section = s; path = NavigationPath() } })) {
                Section("Mediathek") {
                    ForEach(LibrarySection.allCases) { s in
                        Label(s.title, systemImage: s.icon).tag(s)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) { accountFooter }
        } content: {
            CategoryColumn(section: section, selection: categoryID, filter: $categoryFilter, editing: section == .live && editingLive)
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 380)
        } detail: {
            NavigationStack(path: $path) {
                detail
                    .navigationDestination(for: Movie.self) { MovieDetailView(movie: $0) }
                    .navigationDestination(for: Series.self) { SeriesDetailView(series: $0) }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: searchPrompt)
        .onChange(of: query) { _, _ in path = NavigationPath() }
        .onChange(of: section) { _, new in if new != .live { editingLive = false } }
        .toolbar {
            if section == .live {
                ToolbarItem {
                    Picker("Ansicht", selection: $liveMode) {
                        Label("Liste", systemImage: "list.bullet").tag(LiveMode.list)
                        Label("Programm", systemImage: "calendar.day.timeline.left").tag(LiveMode.guide)
                    }
                    .pickerStyle(.segmented)
                    .help("Senderliste oder Programmraster")
                    .disabled(editingLive)
                }
                ToolbarItem {
                    Button(editingLive ? "Fertig" : "Bearbeiten") { setEditingLive(!editingLive) }
                        .help("Kategorien und Sender aus- oder wieder einblenden")
                }
            }
            ToolbarItem {
                Button {
                    Task { await app.loadCatalog(forceRefresh: true) }
                } label: {
                    if app.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Aktualisieren", systemImage: "arrow.clockwise")
                    }
                }
                .help("Katalog vom Server neu laden")
                .disabled(app.isLoading)
            }
        }
        #if DEBUG
        .task { await debugScene() }
        #endif
        .onChange(of: app.requestedSection, initial: true) { _, requested in
            guard let requested else { return }
            section = requested
            path = NavigationPath()
            app.requestedSection = nil
        }
        .onChange(of: app.nowPlaying) { _, item in
            if item != nil { openWindow(id: "player") }
        }
        .overlay {
            if app.channels.isEmpty && app.movies.isEmpty {
                if app.isLoading {
                    ProgressView("Katalog wird geladen …")
                        .padding(32)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                } else if let error = app.loadError {
                    ContentUnavailableView {
                        Label("Katalog nicht verfügbar", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Erneut versuchen") { Task { await app.loadCatalog(forceRefresh: true) } }
                    }
                }
            }
        }
    }

    /// Edit mode only lists, the guide stays read-only.
    private func setEditingLive(_ editing: Bool) {
        if editing && liveMode == .guide { liveMode = .list }
        editingLive = editing
    }

    #if DEBUG
    /// Screenshot runs: IPTV_SCENE=<live|movies|series|favorites>[:<category id>[:movie|series:<id>]],
    /// IPTV_SCENE=live:<category id>:edit[:<s>] enters Live TV's Edit mode (after <s> seconds).
    private func debugScene() async {
        guard let scene = ProcessInfo.processInfo.environment["IPTV_SCENE"] else { return }
        let parts = scene.split(separator: ":").map(String.init)
        guard let target = LibrarySection(rawValue: parts[0]) else { return }
        section = target
        if parts.count > 1 { categoryBySection[target] = parts[1] }
        while app.channels.isEmpty && app.movies.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
        if target == .live, parts.count > 2, parts[2] == "edit" {
            try? await Task.sleep(for: .seconds(parts.count > 3 ? Double(parts[3]) ?? 0 : 0))
            setEditingLive(true)
            return
        }
        guard parts.count > 3, let id = Int(parts[3]) else { return }
        try? await Task.sleep(for: .milliseconds(500))
        if parts[2] == "movie", let movie = app.movies.first(where: { $0.id == id }) { path.append(movie) }
        if parts[2] == "series", let show = app.series.first(where: { $0.id == id }) { path.append(show) }
    }
    #endif

    private var searchPrompt: LocalizedStringKey {
        switch section {
        case .live: return "Sender suchen"
        case .movies: return "Filme suchen"
        case .series: return "Serien suchen"
        case .favorites: return "Favoriten durchsuchen"
        case .recordings: return "Aufnahmen durchsuchen"
        }
    }

    @ViewBuilder
    private var detail: some View {
        let category = categoryBySection[section] ?? allCategoryID
        switch section {
        case .live:
            switch liveMode {
            case .list: ChannelListView(categoryID: category, query: query, editing: editingLive)
            case .guide: GuideView(categoryID: category, query: query)
            }
        case .movies:
            MovieGridView(categoryID: category, query: query)
        case .series:
            SeriesGridView(categoryID: category, query: query)
        case .favorites:
            FavoritesView(kind: category, query: query)
        case .recordings:
            RecordingsView(filter: category, query: query)
        }
    }

    private var accountFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let account = app.account, let expires = account.expiresAt {
                Text("Gültig bis \(expires.formatted(date: .abbreviated, time: .omitted))")
            }
            if let updated = app.lastUpdated {
                Text("Stand \(updated.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

// MARK: - Categories

struct CategoryColumn: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var recorder: Recorder
    let section: LibrarySection
    @Binding var selection: String?
    @Binding var filter: String
    /// Live TV's Edit mode: hidden categories are listed dimmed, every row has a show/hide toggle.
    var editing = false

    var body: some View {
        let rows = categories
        List(selection: $selection) {
            ForEach(rows, id: \.category.id) { row in
                let hideable = section == .live && row.category.id != allCategoryID
                HStack {
                    Text(row.category.name).lineLimit(1)
                        .opacity(row.hidden ? 0.4 : 1)
                    Spacer()
                    if let count = row.count {
                        Text("\(count)").foregroundStyle(.tertiary).monospacedDigit()
                            .opacity(row.hidden ? 0.4 : 1)
                    }
                    if editing && hideable {
                        VisibilityToggle(hidden: row.hidden) { app.setCategory(row.category.id, hidden: !row.hidden) }
                    }
                }
                .tag(row.category.id)
                .contextMenu {
                    if hideable {
                        Button(row.hidden ? "Einblenden" : "Ausblenden") { app.setCategory(row.category.id, hidden: !row.hidden) }
                    }
                }
            }
        }
        .onChange(of: selectionHidden, initial: true) { _, hidden in
            // A hidden category leaves the column outside Edit mode; "All" takes its place.
            if hidden { selection = allCategoryID }
        }
        .safeAreaInset(edge: .top) {
            if section != .favorites && section != .recordings {
                TextField("Kategorien filtern", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .navigationTitle(section.title)
    }

    private struct Row {
        let category: XCategory
        let count: Int?
        var hidden = false
    }

    private var selectionHidden: Bool {
        section == .live && !editing && app.isCategoryHidden(selection ?? allCategoryID)
    }

    private var categories: [Row] {
        let source: [XCategory]
        let counts: (String) -> Int?
        let total: Int
        switch section {
        case .live:
            // Outside Edit mode without hidden categories, and counting visible channels only.
            let categories = app.visibleCategories(app.liveCategories)
            source = editing ? categories : categories.filter { !app.isCategoryHidden($0.id) }
            counts = editing ? { app.channelsByCategory[$0]?.count } : { app.visibleChannelCounts[$0] }
            total = editing ? app.channels.count : app.visibleChannelTotal
        case .movies:
            source = app.visibleCategories(app.movieCategories)
            counts = { app.moviesByCategory[$0]?.count }
            total = app.movies.count
        case .series:
            source = app.visibleCategories(app.seriesCategories)
            counts = { app.seriesByCategory[$0]?.count }
            total = app.series.count
        case .favorites:
            // Hidden channels are not listed under Favorites, so they are not counted either.
            let hiddenLive = app.favorites.filter { key in
                key.hasPrefix("live:") && Int(key.dropFirst(5)).flatMap(app.channel).map(app.isHidden) == true
            }.count
            return [
                Row(category: XCategory(id: allCategoryID, name: String(localized: "Alle Favoriten")), count: app.favorites.count - hiddenLive),
                Row(category: XCategory(id: "live", name: String(localized: "Sender")), count: app.favorites.filter { $0.hasPrefix("live:") }.count - hiddenLive),
                Row(category: XCategory(id: "movie", name: String(localized: "Filme")), count: app.favorites.filter { $0.hasPrefix("movie:") }.count),
                Row(category: XCategory(id: "series", name: String(localized: "Serien")), count: app.favorites.filter { $0.hasPrefix("series:") }.count),
            ]
        case .recordings:
            let upcoming = recorder.recordings.filter(\.isUpcomingOrRunning).count
            return [
                Row(category: XCategory(id: allCategoryID, name: String(localized: "Alle Aufnahmen")), count: recorder.recordings.count),
                Row(category: XCategory(id: "upcoming", name: String(localized: "Geplant")), count: upcoming),
                Row(category: XCategory(id: "done", name: String(localized: "Aufgenommen")), count: recorder.recordings.count - upcoming),
            ]
        }
        let needle = makeSearchKey(filter)
        let filtered = needle.isEmpty ? source : source.filter { makeSearchKey($0.name).contains(needle) }
        let all = Row(category: XCategory(id: allCategoryID, name: String(localized: "Alle")), count: total)
        return [all] + filtered.map { Row(category: $0, count: counts($0.id), hidden: section == .live && app.isCategoryHidden($0.id)) }
    }
}
