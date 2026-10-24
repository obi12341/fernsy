import Combine
import Foundation
import SwiftUI

enum LibrarySection: String, Hashable, CaseIterable, Identifiable {
    case live, movies, series, favorites, recordings
    case jellyfinHome, jellyfinFilms, jellyfinSeries
    var id: String { rawValue }

    /// Sections of the IPTV account and of the Jellyfin account (sidebar groups).
    static let iptv: [LibrarySection] = [.live, .movies, .series, .favorites, .recordings]
    static let jellyfin: [LibrarySection] = [.jellyfinHome, .jellyfinFilms, .jellyfinSeries]

    var isJellyfin: Bool { Self.jellyfin.contains(self) }

    var title: String {
        switch self {
        case .live: return String(localized: "Live TV")
        case .movies: return String(localized: "Filme")
        case .series: return String(localized: "Serien")
        case .favorites: return String(localized: "Favoriten")
        case .recordings: return String(localized: "Aufnahmen")
        case .jellyfinHome: return String(localized: "Start")
        case .jellyfinFilms: return String(localized: "Filme")
        case .jellyfinSeries: return String(localized: "Serien")
        }
    }

    var icon: String {
        switch self {
        case .live: return "dot.radiowaves.left.and.right"
        case .movies: return "film"
        case .series: return "tv"
        case .favorites: return "star"
        case .recordings: return "record.circle"
        case .jellyfinHome: return "house"
        case .jellyfinFilms: return "film"
        case .jellyfinSeries: return "tv"
        }
    }
}

/// What the player window should show.
struct PlayItem: Equatable {
    enum Kind: Equatable {
        case live(channelId: Int, categoryId: String?)
        case movie(id: Int)
        case episode(id: String, seriesId: Int)
        case recording(id: UUID)
        /// A Jellyfin film or episode, started at `startAt` seconds.
        case jellyfin(itemId: String, startAt: Double, seriesId: String? = nil)
    }

    let kind: Kind
    let title: String
    let subtitle: String?
    let url: URL

    var isLive: Bool {
        if case .live = kind { return true }
        return false
    }

    var resumeKey: String? {
        switch kind {
        case .live: return nil
        case .movie(let id): return "movie.\(id)"
        case .episode(let id, _): return "episode.\(id)"
        case .recording(let id): return "recording.\(id.uuidString)"
        case .jellyfin: return nil // resume positions live on the server
        }
    }

    /// What is played, for the log (no URL: it carries the account's credentials).
    var logDescription: String {
        switch kind {
        case .live(let id, _): return "channel \(id)"
        case .movie(let id): return "film \(id)"
        case .episode(let id, _): return "episode \(id)"
        case .recording: return "recording"
        case .jellyfin(let id, let startAt, _): return "Jellyfin item \(id)\(startAt > 0 ? " at \(Int(startAt)) s" : "")"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var credentials: XtreamCredentials? {
        didSet {
            if credentials?.accountKey != oldValue?.accountKey {
                recorder.activate(accountKey: credentials?.accountKey)
                loadVisibility()
            }
        }
    }
    @Published private(set) var account: AccountInfo? {
        didSet { updateConnectionLimit() }
    }

    @Published private(set) var liveCategories: [XCategory] = []
    @Published private(set) var movieCategories: [XCategory] = []
    @Published private(set) var seriesCategories: [XCategory] = []
    @Published private(set) var channels: [LiveChannel] = []
    @Published private(set) var movies: [Movie] = []
    @Published private(set) var series: [Series] = []

    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    /// The last background refresh failed while the cached catalog is shown (Live TV's notice).
    @Published private(set) var refreshError: String?
    @Published private(set) var lastUpdated: Date?

    @Published private(set) var favorites: Set<String>
    /// Live channels played last, newest first (Live TV › "Zuletzt gesehen").
    @Published private(set) var recentChannels: [Int]
    /// Channels the provider reported offline when played in this run (cleared by a successful start).
    @Published var offlineChannels: Set<Int> = []
    static let recentLimit = 20
    /// Hidden live categories and channels of the signed-in account.
    @Published private(set) var visibility = ChannelVisibility() {
        didSet { updateVisibleCounts() }
    }
    @Published var showAdult: Bool {
        didSet { UserDefaults.standard.set(showAdult, forKey: "library.showAdult") }
    }

    @Published var nowPlaying: PlayItem? {
        didSet {
            if case .live(let id, _)? = nowPlaying?.kind, nowPlaying != oldValue { noteRecent(id) }
            if let item = nowPlaying, item != oldValue {
                AppLog.info(.player, "play \(item.logDescription): \(item.title)\(item.subtitle.map { " – \($0)" } ?? "")")
            } else if nowPlaying == nil, oldValue != nil {
                AppLog.info(.player, "player closed")
            }
            updatePlayerTuner()
        }
    }
    /// The player runs in Picture in Picture with its window hidden: new items play there and
    /// must not bring the player window back.
    @Published var isPictureInPictureActive = false
    /// Set from outside the library window (menu bar): the section it should show.
    @Published var requestedSection: LibrarySection?
    /// The tuner the player watches live TV through (shared with recordings of that channel).
    @Published private(set) var playerTuner: LiveTuner?

    let epg = EPGStore()
    let tuners = TunerPool()
    let recorder = Recorder()
    /// The Jellyfin account, independent of the IPTV one.
    /// Debug sign-ins (JF_SERVER) leave the keychain alone unless they use their own items
    /// (JF_KEYCHAIN_SUFFIX) – then only those, even with FERNSY_NO_KEYCHAIN, so a debug build
    /// never reads the installed app's items (which would ask for keychain access).
    let jellyfin = JellyfinStore(skipKeychain: ProcessInfo.processInfo.environment["JF_KEYCHAIN_SUFFIX"] == nil
        && (AppModel.skipKeychain || ProcessInfo.processInfo.environment["JF_SERVER"] != nil))
    /// Mirrors `jellyfin.session != nil`, so views observing AppModel follow it.
    @Published private(set) var hasJellyfin = false

    static let timeshiftMinutesKey = "timeshift.minutes"

    private(set) var channelsByCategory: [String: [LiveChannel]] = [:]
    private(set) var moviesByCategory: [String: [Movie]] = [:]
    private(set) var seriesByCategory: [String: [Series]] = [:]
    /// Live channels per category and in total, without hidden ones.
    private(set) var visibleChannelCounts: [String: Int] = [:]
    private(set) var visibleChannelTotal = 0

    private var logSecrets: Set<AnyCancellable> = []

    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "library.favorites") ?? [])
        recentChannels = Self.skipKeychain ? [] : (UserDefaults.standard.array(forKey: "live.recent") as? [Int] ?? [])
        showAdult = UserDefaults.standard.bool(forKey: "library.showAdult")
        UserDefaults.standard.register(defaults: [Self.timeshiftMinutesKey: 60])
        recorder.app = self
        tuners.onOffline = { [weak self] channelId, offline in
            guard let self else { return }
            if offline { offlineChannels.insert(channelId) } else { offlineChannels.remove(channelId) }
        }
        jellyfin.$session.map { $0 != nil }.removeDuplicates().assign(to: &$hasJellyfin)
        // Passwords and tokens never reach the log.
        $credentials.map { $0?.password }.removeDuplicates()
            .sink { AppLog.shared.setSecret("xtream", $0) }.store(in: &logSecrets)
        jellyfin.$session.map { $0?.token }.removeDuplicates()
            .sink { AppLog.shared.setSecret("jellyfin", $0) }.store(in: &logSecrets)
        AppDelegate.app = self
        applyTimeshiftSetting()
        updateConnectionLimit()
        if !Self.skipKeychain, let saved = CredentialStore.load() {
            credentials = saved
            Task { await loadCatalog(forceRefresh: false) }
        }
        #if DEBUG
        debugBootstrap()
        #endif
        recorder.activate(accountKey: credentials?.accountKey)
        loadVisibility()
    }

    func applyTimeshiftSetting() {
        tuners.keepSeconds = Double(UserDefaults.standard.integer(forKey: Self.timeshiftMinutesKey)) * 60
    }

    private func updateConnectionLimit() {
        var limit = max(1, account?.maxConnections ?? 1)
        #if DEBUG
        if let forced = ProcessInfo.processInfo.environment["IPTV_MAXCONN"].flatMap(Int.init) { limit = forced }
        #endif
        tuners.limit = limit
    }

    /// Development login from IPTV_SERVER/IPTV_USER/IPTV_PASS. Takes precedence over the
    /// keychain, which a freshly built debug binary may not read without a password prompt.
    private static var debugCredentials: XtreamCredentials? {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard let server = env["IPTV_SERVER"], let user = env["IPTV_USER"], let pass = env["IPTV_PASS"] else { return nil }
        return XtreamCredentials(server: server, username: user, password: pass)
        #else
        return nil
        #endif
    }

    #if DEBUG
    private var debugFavoritesInMemory = false

    /// Development hook: IPTV_SERVER/IPTV_USER/IPTV_PASS log in without the keychain,
    /// IPTV_AUTOPLAY=live:<id> | movie:<id> starts playback once the catalog is loaded,
    /// IPTV_TESTHIDE hides channels and categories (see below).
    private func debugBootstrap() {
        let env = ProcessInfo.processInfo.environment
        if let debug = Self.debugCredentials {
            credentials = debug
            Task { await loadCatalog(forceRefresh: false) }
        }
        if let size = env["IPTV_WINDOW"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            // Screenshot runs: keep every titled window at this size (points, frame incl. title bar).
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
                    guard window.frame.size != CGSize(width: size[0], height: size[1]) else { continue }
                    window.setFrame(CGRect(origin: CGPoint(x: 80, y: 80), size: CGSize(width: size[0], height: size[1])), display: true)
                }
            }
        }
        if let spec = env["IPTV_TESTRECORD"]?.split(separator: ":").compactMap({ Double($0) }), spec.count == 3 || spec.count == 5 {
            // IPTV_TESTRECORD=<channel>:<starts in s>:<seconds>[:<before min>:<after min>]: a show
            // recorded without padding, or with the given padding.
            Task {
                while channels.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                guard let channel = channel(Int(spec[0])) else { return }
                let start = Date().addingTimeInterval(spec[1])
                let entry = EPGEntry(id: "test", title: "Test \(Int(spec[0]))", description: "", start: start, end: start.addingTimeInterval(spec[2]))
                recorder.schedule(entry, on: channel, padding: spec.count == 5 ? (spec[3] * 60, spec[4] * 60) : (0, 0))
            }
        }
        if let spec = env["IPTV_TESTPADDING"]?.split(separator: ":").compactMap({ Double($0) }), spec.count == 3 {
            // IPTV_TESTPADDING=<after s>:<before min>:<after min>: as if Settings changed (without
            // touching the shared defaults of an installed Fernsy).
            DispatchQueue.main.asyncAfter(deadline: .now() + spec[0]) { [recorder] in
                recorder.applyPadding(before: spec[1] * 60, after: spec[2] * 60)
            }
        }
        if let list = env["IPTV_FAVORITES"] {
            // IPTV_FAVORITES=live:101,movie:5: these favorites, in memory only (the shared
            // defaults of an installed Fernsy stay untouched, also when toggling).
            favorites = Set(list.split(separator: ",").map(String.init))
            debugFavoritesInMemory = true
        }
        if let spec = env["IPTV_TESTHIDE"] {
            // IPTV_TESTHIDE=channel:102,category:3,wait:20,show:channel:102: hides (or with
            // "show:" shows) live channels and categories in order once the catalog is loaded,
            // "wait:<s>" pauses in between.
            Task {
                while channels.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                for item in spec.split(separator: ",") {
                    var parts = item.split(separator: ":").map(String.init)
                    let hidden = parts.first != "show"
                    if !hidden { parts.removeFirst() }
                    guard parts.count == 2 else { continue }
                    switch parts[0] {
                    case "wait": try? await Task.sleep(for: .seconds(Double(parts[1]) ?? 0))
                    case "channel": if let id = Int(parts[1]) { setChannel(id, hidden: hidden) }
                    case "category": setCategory(parts[1], hidden: hidden)
                    default: continue
                    }
                    debugLog("[test] test \(item): \(visibleChannelTotal) of \(channels.count) channels visible")
                }
            }
        }
        if let raw = env["IPTV_PLAYURL"], let url = URL(string: raw) {
            // IPTV_PLAYURL=<url>: play any URL as a movie (VOD path, range requests), e.g. a
            // media server's direct stream for format tests. Resume key: movie.-1.
            Task {
                try? await Task.sleep(for: .seconds(1))
                nowPlaying = PlayItem(kind: .movie(id: -1), title: url.lastPathComponent, subtitle: nil, url: url)
            }
        }
        if let spec = env["IPTV_TESTSIGNOUT"]?.split(separator: ":"), spec.count == 2, let delay = Double(spec[1]) {
            // IPTV_TESTSIGNOUT=<iptv|jellyfin>:<s>: sign out of that account after <s> seconds.
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
                debugLog("[test] signing out of \(spec[0])")
                if spec[0] == "iptv" { logout() } else { jellyfin.signOut() }
            }
        }
        if env["IPTV_TRACKSELFTEST"] == "1" { TrackChooser.selfTest() }
        if env["IPTV_LOGSELFTEST"] == "1" { AppLog.shared.selfTest() }
        if env["IPTV_LOGOTONETEST"] == "1" { LogoTile.selfTest() }
        if env["IPTV_NAMETEST"] == "1" { ChannelName.selfTest() }
        if let appearance = env["IPTV_APPEARANCE"] {
            // IPTV_APPEARANCE=light|dark: one run in that appearance, without touching the system setting.
            NSApp.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        }
        if let spec = env["JF_AUTOPLAY"] {
            // JF_AUTOPLAY=<item id>[:<start s>]: play a Jellyfin film or episode once signed in.
            let parts = spec.split(separator: ":").map(String.init)
            Task {
                while jellyfin.films.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                await jellyfin.loadDetail(parts[0])
                guard var item = jellyfin.details[parts[0]] else { debugLog("[test] autoplay: unknown item"); return }
                if parts.count > 1, let start = Double(parts[1]) {
                    item.userData = (item.userData ?? JFUserData())
                    item.userData?.playbackPositionTicks = Int64(start * 10_000_000)
                }
                play(jellyfin: item)
            }
        }
        if let spec = env["IPTV_TESTSWITCH"]?.split(separator: ":"), spec.count == 3,
           let after = Double(spec[0]), let id = Int(spec[2]) {
            // IPTV_TESTSWITCH=<s>:<live|movie>:<id>: start another item after <s> seconds the way
            // the main window does (e.g. while Picture in Picture runs).
            Task {
                try? await Task.sleep(for: .seconds(after))
                debugLog("[test] switch to \(spec[1]) \(id)")
                if spec[1] == "live", let channel = channel(id) { play(channel) }
                if spec[1] == "movie", let movie = movies.first(where: { $0.id == id }) { play(movie) }
            }
        }
        guard let auto = env["IPTV_AUTOPLAY"] else { return }
        let parts = auto.split(separator: ":")
        guard parts.count >= 2, let id = Int(parts[1]) else { return }
        Task {
            while channels.isEmpty && movies.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .seconds(1))
            if parts[0] == "live", let channel = channel(id) { play(channel) }
            if parts[0] == "movie", let movie = movies.first(where: { $0.id == id }) { play(movie) }
            if parts[0] == "recording", recorder.recordings.indices.contains(id) { play(recorder.recordings[id]) }
            // episode:<series id>:<n> – the n-th episode over all seasons (1-based).
            if parts[0] == "episode", parts.count == 3, let n = Int(parts[2]), let show = series.first(where: { $0.id == id }),
               let info = try? await client?.seriesInfo(id) {
                let all = info.seasons.keys.sorted().flatMap { info.seasons[$0] ?? [] }
                if all.indices.contains(n - 1) { play(all[n - 1], of: show) }
            }
        }
    }
    #endif

    var client: XtreamClient? { credentials.map(XtreamClient.init) }

    // MARK: Account

    /// FERNSY_NO_KEYCHAIN: neither read, write nor delete the stored login – for the build
    /// script's launch smoke test and for demo recordings next to a real installation.
    static var skipKeychain: Bool {
        debugCredentials != nil || ProcessInfo.processInfo.environment["FERNSY_NO_KEYCHAIN"] != nil
    }

    func login(_ creds: XtreamCredentials) async throws {
        let info: AccountInfo
        do {
            info = try await XtreamClient(credentials: creds).account()
        } catch {
            AppLog.error(.app, "IPTV sign-in at \(creds.baseURL?.host() ?? creds.server) failed: \(error.localizedDescription)")
            throw error
        }
        AppLog.info(.app, "signed in to IPTV account at \(creds.baseURL?.host() ?? creds.server)")
        if !Self.skipKeychain { CredentialStore.save(creds) }
        epg.removeAll()
        credentials = creds
        account = info
        await loadCatalog(forceRefresh: true)
    }

    func logout() {
        AppLog.info(.app, "signed out of the IPTV account")
        nowPlaying = nil
        tuners.stopAll()
        periodicRefresh?.cancel()
        periodicRefresh = nil
        lastRefresh = nil
        if !Self.skipKeychain { CredentialStore.delete() }
        credentials = nil
        account = nil
        refreshError = nil
        liveCategories = []; movieCategories = []; seriesCategories = []
        channels = []; movies = []; series = []
        channelsByCategory = [:]; moviesByCategory = [:]; seriesByCategory = [:]
        updateVisibleCounts()
        epg.removeAll()
    }

    // MARK: Catalog
    //
    // Stale-while-revalidate: the last downloaded catalog is shown straight from disk
    // (live channels first, they are the smallest and most used), then every section
    // is re-downloaded in the background and only re-applied if its bytes changed.

    /// Sections of the catalog that are decoded and applied independently.
    private enum CatalogSection: CaseIterable {
        case live, movies, series

        var actions: [CatalogAction] {
            switch self {
            case .live: return [.liveCategories, .liveStreams]
            case .movies: return [.vodCategories, .vodStreams]
            case .series: return [.seriesCategories, .series]
            }
        }
    }

    private enum DecodedSection: Sendable {
        case live([XCategory], [LiveChannel])
        case movies([XCategory], [Movie])
        case series([XCategory], [Series])
    }

    private static let refreshInterval: TimeInterval = 6 * 3600
    private var lastRefresh: Date?
    private var refreshInFlight = false
    private var periodicRefresh: Task<Void, Never>?

    private var cacheDirectory: URL? {
        guard let credentials else { return nil }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Fernsy/\(credentials.accountKey)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Shows the cached catalog immediately (if any) and refreshes it in the background.
    /// `forceRefresh` bypasses the "refreshed a moment ago" check (manual refresh).
    func loadCatalog(forceRefresh: Bool) async {
        guard let client, let dir = cacheDirectory else { return }
        loadError = nil

        if channels.isEmpty && movies.isEmpty && series.isEmpty {
            await loadFromCache(dir)
        }
        if account == nil {
            Task { account = try? await client.account() }
        }
        startPeriodicRefresh()

        if !forceRefresh, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 300 { return }
        await refresh(client: client, dir: dir)
    }

    private func loadFromCache(_ dir: URL) async {
        let stamp = dir.appendingPathComponent("updated")
        guard let cachedAt = (try? FileManager.default.attributesOfItem(atPath: stamp.path)[.modificationDate]) as? Date else { return }
        lastUpdated = cachedAt

        let started = Date()
        if let live = await Self.decode(.live, from: dir) { apply(live) }
        AppLog.detail(.catalog, "live from cache in \(Int(Date().timeIntervalSince(started) * 1000)) ms (\(channels.count) channels)")

        await withTaskGroup(of: DecodedSection?.self) { group in
            group.addTask { await Self.decode(.movies, from: dir) }
            group.addTask { await Self.decode(.series, from: dir) }
            for await section in group {
                if let section { apply(section) }
            }
        }
        AppLog.detail(.catalog, "full cache in \(Int(Date().timeIntervalSince(started) * 1000)) ms (\(movies.count) movies, \(series.count) series)")
    }

    private func refresh(client: XtreamClient, dir: URL) async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        isLoading = true
        defer {
            refreshInFlight = false
            isLoading = false
        }

        let started = Date()
        do {
            #if DEBUG
            // IPTV_TESTCATALOGFAIL=1: the refresh fails as if the provider were unreachable.
            if ProcessInfo.processInfo.environment["IPTV_TESTCATALOGFAIL"] != nil { throw URLError(.cannotConnectToHost) }
            #endif
            // Download everything, keep only actions whose payload changed.
            let changed: Set<CatalogAction> = try await withThrowingTaskGroup(of: CatalogAction?.self) { group in
                for action in CatalogAction.allCases {
                    group.addTask {
                        let data = try await client.catalog(action)
                        let file = dir.appendingPathComponent(action.rawValue + ".json")
                        if let old = try? Data(contentsOf: file), old == data { return nil }
                        try data.write(to: file, options: .atomic)
                        return action
                    }
                }
                var result = Set<CatalogAction>()
                for try await action in group { if let action { result.insert(action) } }
                return result
            }
            FileManager.default.createFile(atPath: dir.appendingPathComponent("updated").path, contents: Data())
            lastRefresh = Date()
            lastUpdated = lastRefresh

            for section in CatalogSection.allCases where !changed.isDisjoint(with: section.actions) || isEmpty(section) {
                if let decoded = await Self.decode(section, from: dir) { apply(decoded) }
            }
            refreshError = nil
            AppLog.info(.catalog, "refresh in \(Int(Date().timeIntervalSince(started) * 1000)) ms, changed: \(changed.map(\.rawValue).sorted())")
        } catch {
            // Without cached data the whole library says so; with it, Live TV shows a notice.
            if channels.isEmpty && movies.isEmpty && series.isEmpty {
                loadError = error.localizedDescription
            } else {
                refreshError = error.localizedDescription
            }
            AppLog.error(.catalog, "refresh failed: \(error.localizedDescription)")
        }
    }

    private func startPeriodicRefresh() {
        guard periodicRefresh == nil else { return }
        periodicRefresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
                guard let self, !Task.isCancelled else { return }
                await self.loadCatalog(forceRefresh: true)
            }
        }
    }

    private func isEmpty(_ section: CatalogSection) -> Bool {
        switch section {
        case .live: return channels.isEmpty
        case .movies: return movies.isEmpty
        case .series: return series.isEmpty
        }
    }

    private nonisolated static func decode(_ section: CatalogSection, from dir: URL) async -> DecodedSection? {
        await Task.detached(priority: .userInitiated) { () -> DecodedSection? in
            func load<T: Decodable>(_ action: CatalogAction, _ type: T.Type) -> T? {
                guard let data = try? Data(contentsOf: dir.appendingPathComponent(action.rawValue + ".json")) else { return nil }
                return try? JSONDecoder().decode(T.self, from: data)
            }
            switch section {
            case .live:
                guard let streams = load(.liveStreams, [LiveChannel].self) else { return nil }
                return .live(load(.liveCategories, [XCategory].self) ?? [], streams)
            case .movies:
                guard let streams = load(.vodStreams, [Movie].self) else { return nil }
                return .movies(load(.vodCategories, [XCategory].self) ?? [], streams)
            case .series:
                guard let streams = load(.series, [Series].self) else { return nil }
                return .series(load(.seriesCategories, [XCategory].self) ?? [], streams)
            }
        }.value
    }

    private func apply(_ section: DecodedSection) {
        switch section {
        case .live(let categories, let list):
            channelsByCategory = Dictionary(grouping: list) { $0.categoryId ?? "" }
            liveCategories = categories
            channels = list
            updateVisibleCounts()
        case .movies(let categories, let list):
            moviesByCategory = Dictionary(grouping: list) { $0.categoryId ?? "" }
            movieCategories = categories
            movies = list
        case .series(let categories, let list):
            seriesByCategory = Dictionary(grouping: list) { $0.categoryId ?? "" }
            seriesCategories = categories
            series = list
        }
    }

    // MARK: Adult filter

    private static let adultMarkers = ["xxx", "adult", "+18", "18+", "for adults", "erotik"]

    func isAdultCategory(_ category: XCategory) -> Bool {
        let name = category.name.lowercased()
        return Self.adultMarkers.contains { name.contains($0) }
    }

    func visibleCategories(_ list: [XCategory]) -> [XCategory] {
        showAdult ? list : list.filter { !isAdultCategory($0) }
    }

    // MARK: Hidden categories and channels

    func isHidden(_ channel: LiveChannel) -> Bool {
        visibility.hiddenChannels.contains(channel.id) || visibility.hiddenCategories.contains(channel.categoryId ?? "")
    }

    func isCategoryHidden(_ id: String) -> Bool { visibility.hiddenCategories.contains(id) }

    func isChannelHidden(_ id: Int) -> Bool { visibility.hiddenChannels.contains(id) }

    func setCategory(_ id: String, hidden: Bool) {
        guard isCategoryHidden(id) != hidden else { return }
        var value = visibility
        if hidden { value.hiddenCategories.insert(id) } else { value.hiddenCategories.remove(id) }
        storeVisibility(value)
    }

    func setChannel(_ id: Int, hidden: Bool) {
        guard isChannelHidden(id) != hidden else { return }
        var value = visibility
        if hidden { value.hiddenChannels.insert(id) } else { value.hiddenChannels.remove(id) }
        storeVisibility(value)
    }

    /// Edit mode's "Show All": nothing hidden any more.
    func showAllChannels() {
        guard !visibility.hiddenCategories.isEmpty || !visibility.hiddenChannels.isEmpty else { return }
        var value = visibility
        value.hiddenCategories = []
        value.hiddenChannels = []
        storeVisibility(value)
    }

    var hasHiddenChannels: Bool { !visibility.hiddenCategories.isEmpty || !visibility.hiddenChannels.isEmpty }

    private func storeVisibility(_ value: ChannelVisibility) {
        var value = value
        value.modifiedAt = Date()
        visibility = value
        if let dir = cacheDirectory { value.save(to: dir) }
    }

    /// The signed-in account's choice; signed out, nothing is hidden (the file stays).
    private func loadVisibility() {
        visibility = cacheDirectory.map(ChannelVisibility.load) ?? ChannelVisibility()
        AppLog.detail(.app, "\(credentials?.accountKey ?? "-"): \(visibility.hiddenCategories.count) categories, \(visibility.hiddenChannels.count) channels hidden")
    }

    private func updateVisibleCounts() {
        var counts: [String: Int] = [:]
        for channel in channels where !isHidden(channel) { counts[channel.categoryId ?? "", default: 0] += 1 }
        visibleChannelCounts = counts
        visibleChannelTotal = counts.values.reduce(0, +)
    }

    // MARK: Favorites

    func isFavorite(_ key: String) -> Bool { favorites.contains(key) }

    private func noteRecent(_ channelId: Int) {
        var list = recentChannels.filter { $0 != channelId }
        list.insert(channelId, at: 0)
        recentChannels = Array(list.prefix(Self.recentLimit))
        // Test runs (no keychain) keep it in memory: they share the installed app's defaults.
        if !Self.skipKeychain { UserDefaults.standard.set(recentChannels, forKey: "live.recent") }
    }

    func toggleFavorite(_ key: String) {
        if favorites.contains(key) { favorites.remove(key) } else { favorites.insert(key) }
        #if DEBUG
        if debugFavoritesInMemory { return }
        #endif
        UserDefaults.standard.set(Array(favorites), forKey: "library.favorites")
    }

    // MARK: Playback

    private func updatePlayerTuner() {
        guard case .live(let id, _)? = nowPlaying?.kind, let url = nowPlaying?.url else {
            if let old = playerTuner?.channelId { tuners.release(old, owner: .player) }
            playerTuner = nil
            return
        }
        guard playerTuner?.channelId != id || playerTuner?.isActive == false else { return }
        // Release first: on single-connection accounts the old stream has to go.
        if let old = playerTuner?.channelId { tuners.release(old, owner: .player) }
        playerTuner = tuners.acquire(id, url: url, owner: .player)
    }

    /// "Try again" after the player's tuner gave up.
    func retuneForPlayer() {
        guard let tuner = playerTuner, !tuner.isActive else { return }
        tuners.release(tuner.channelId, owner: .player)
        playerTuner = nil
        updatePlayerTuner()
    }

    /// Asks first when the account has no free connection because recordings hold it.
    func play(_ channel: LiveChannel, force: Bool = false) {
        guard let url = client?.liveURL(channel.id) else { return }
        let item = PlayItem(kind: .live(channelId: channel.id, categoryId: channel.categoryId),
                            title: channel.displayName, subtitle: nil, url: url)
        let blocking = recordingsBlocking(channel.id)
        guard !force, let first = blocking.first else {
            nowPlaying = item
            return
        }
        Task {
            let accepted = await Prompt.ask(
                title: String(localized: "Aufnahme läuft"),
                message: String(localized: "Gerade wird „\(first.title)“ auf \(first.channelName) aufgenommen. Dein Zugang erlaubt nur \(tuners.limit) Stream(s) gleichzeitig. Aufnahme beenden und auf \(channel.displayName) umschalten?"),
                confirm: String(localized: "Aufnahme beenden und umschalten"), cancel: String(localized: "Abbrechen"))
            guard accepted else { return }
            for recording in blocking { recorder.stop(recording.id) }
            nowPlaying = item
        }
    }

    /// Running recordings that hold the connections the player would need for `channelId`.
    private func recordingsBlocking(_ channelId: Int) -> [Recording] {
        let blockers = tuners.blockers(for: channelId, as: .player)
        return recorder.recordings.filter { r in
            r.status == .recording && blockers.contains { $0.owners.contains(.recording(r.id)) }
        }
    }

    /// Plays a Jellyfin film or episode; series start with their Next Up episode.
    /// Language rules for a playback: the series' remembered choice, else the settings.
    func trackPreferences(for item: PlayItem) -> TrackPreferences {
        guard let key = Self.seriesTrackKey(item), let data = seriesTracks[key],
              let stored = try? JSONDecoder().decode(TrackPreferences.self, from: data) else { return TrackPreferences.settings }
        return stored
    }

    /// The user picked tracks in the player: series episodes keep that choice for the next ones.
    func rememberTracks(_ preferences: TrackPreferences, for item: PlayItem) {
        guard let key = Self.seriesTrackKey(item), let data = try? JSONEncoder().encode(preferences) else { return }
        var all = seriesTracks
        all[key] = data
        var order = (UserDefaults.standard.stringArray(forKey: Self.seriesTracksStore + ".order") ?? []).filter { $0 != key } + [key]
        while order.count > 200 { all[order.removeFirst()] = nil }
        UserDefaults.standard.set(all, forKey: Self.seriesTracksStore)
        UserDefaults.standard.set(order, forKey: Self.seriesTracksStore + ".order")
        AppLog.detail(.player, "remembered for \(key): audio \(preferences.audioLanguage ?? "system"), subtitles \(preferences.subtitles.stored)")
    }

    private var seriesTracks: [String: Data] {
        UserDefaults.standard.dictionary(forKey: Self.seriesTracksStore) as? [String: Data] ?? [:]
    }

    /// Debug runs can keep their memory apart from the user's (IPTV_TRACKSTORE=test).
    static var seriesTracksStore: String {
        #if DEBUG
        if let suffix = ProcessInfo.processInfo.environment["IPTV_TRACKSTORE"] { return "tracks.series.\(suffix)" }
        #endif
        return "tracks.series"
    }

    private static func seriesTrackKey(_ item: PlayItem) -> String? {
        switch item.kind {
        case .episode(_, let seriesId): return "iptv.\(seriesId)"
        case .jellyfin(_, _, let seriesId?): return "jellyfin.\(seriesId)"
        default: return nil
        }
    }

    func play(jellyfin item: JFItem, resume: Bool = true) {
        Task {
            var target = item
            if item.isSeries {
                guard let episode = await jellyfin.episodeToPlay(seriesId: item.id) else { return }
                target = episode
            }
            guard let base = jellyfin.session?.baseURL else { return }
            let start = resume ? Double(target.userData?.playbackPositionTicks ?? 0) / 10_000_000 : 0
            var subtitle: String?
            if target.type == "Episode" {
                let code = [target.parentIndexNumber.map { "S\($0)" }, target.indexNumber.map { "E\($0)" }].compactMap { $0 }.joined()
                subtitle = code.isEmpty ? target.name : "\(code) · \(target.name)"
            }
            nowPlaying = PlayItem(kind: .jellyfin(itemId: target.id, startAt: start, seriesId: target.seriesId), title: target.seriesName ?? target.name,
                                  subtitle: subtitle, url: base)
        }
    }

    func play(_ recording: Recording) {
        guard let url = recorder.fileURL(recording) else { return }
        nowPlaying = PlayItem(kind: .recording(id: recording.id), title: recording.title,
                              subtitle: "\(recording.channelName) · \(recording.start.formatted(date: .abbreviated, time: .shortened))", url: url)
    }

    func play(_ movie: Movie) {
        guard let url = client?.movieURL(movie) else { return }
        nowPlaying = PlayItem(kind: .movie(id: movie.id), title: movie.name, subtitle: nil, url: url)
    }

    func play(_ episode: Episode, of show: Series) {
        guard let url = client?.episodeURL(episode) else { return }
        nowPlaying = PlayItem(kind: .episode(id: episode.id, seriesId: show.id), title: show.name,
                              subtitle: "S\(episode.season) E\(episode.number) · \(episode.title)", url: url)
    }

    /// Channels the player zaps through, hidden ones included: the category the channel was
    /// started from, or everything if that category has no visible channel.
    private func zapOrder(categoryId: String?) -> [LiveChannel] {
        let list = categoryId.flatMap { channelsByCategory[$0] } ?? []
        return list.contains { !isHidden($0) } ? list : channels
    }

    /// The visible channels the player zaps through.
    func zapList(categoryId: String?) -> [LiveChannel] {
        zapOrder(categoryId: categoryId).filter { !isHidden($0) }
    }

    /// The visible channel `offset` steps away from `channelId` (wrapping), with its 1-based
    /// number. From a hidden channel it steps to the visible ones around its place.
    func neighbor(of channelId: Int, categoryId: String?, offset: Int) -> (channel: LiveChannel, number: Int)? {
        let order = zapOrder(categoryId: categoryId)
        let list = order.filter { !isHidden($0) }
        guard !list.isEmpty else { return nil }
        let index: Int
        if let current = list.firstIndex(where: { $0.id == channelId }) {
            index = current + offset
        } else {
            guard offset != 0, let position = order.firstIndex(where: { $0.id == channelId }) else { return nil }
            // Visible channels before the hidden one: the next one down has this index.
            let before = order[..<position].filter { !isHidden($0) }.count
            index = offset > 0 ? before + offset - 1 : before + offset
        }
        let next = (index % list.count + list.count) % list.count
        return (list[next], next + 1)
    }

    func channel(_ id: Int) -> LiveChannel? {
        channels.first { $0.id == id }
    }

    // MARK: Resume positions

    func resumePosition(_ key: String) -> Double {
        UserDefaults.standard.double(forKey: "resume." + key)
    }

    func saveResume(_ key: String, position: Double, duration: Double) {
        let finished = duration > 0 && position > duration - 90
        if position < 30 || finished {
            UserDefaults.standard.removeObject(forKey: "resume." + key)
        } else {
            UserDefaults.standard.set(position, forKey: "resume." + key)
        }
    }
}
