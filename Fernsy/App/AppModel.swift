import Combine
import Foundation
import Network
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
                loadSavedConnectionLimit()
                recorder.activate(accountKey: credentials?.accountKey)
                loadVisibility()
            }
        }
    }
    @Published private(set) var account: AccountInfo? {
        didSet {
            saveConnectionLimit()
            updateConnectionLimit()
        }
    }
    /// The stream limit the provider last reported for this account (`connections.json`), used
    /// until `account` answers again.
    private var savedConnectionLimit: Int?

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
    /// macOS has a network path (Wi-Fi, Ethernet …). False lets the player say "no internet"
    /// instead of naming the provider.
    @Published private(set) var isNetworkAvailable = true
    private let pathMonitor = NWPathMonitor()
    static let recentLimit = 20
    /// Hidden live categories and channels of the signed-in account.
    @Published private(set) var visibility = ChannelVisibility() {
        didSet { updateVisibleCounts() }
    }
    @Published var showAdult: Bool {
        didSet {
            #if DEBUG
            if debugSettingsInMemory { return }
            #endif
            UserDefaults.standard.set(showAdult, forKey: "library.showAdult")
        }
        willSet { if newValue != showAdult { Task { @MainActor in SiriIndex.schedule(self) } } }
    }
    /// Adult channels also appear in "Zuletzt gesehen" (Youth protection; only while
    /// `showAdult` is on).
    @Published var showAdultInRecent: Bool {
        didSet {
            #if DEBUG
            if debugSettingsInMemory { return }
            #endif
            UserDefaults.standard.set(showAdultInRecent, forKey: "library.showAdultInRecent")
        }
    }

    /// The IPTV account's films and series (Settings › Konten). Switched off, they are neither
    /// downloaded nor shown, searched or listed under Favorites; favorites, watched marks and
    /// resume positions stay.
    @Published var showsIPTVMovies: Bool {
        didSet {
            guard showsIPTVMovies != oldValue else { return }
            storeSetting(showsIPTVMovies, "library.iptvMovies")
            catalogSectionSwitched(.movies, on: showsIPTVMovies)
        }
    }
    @Published var showsIPTVSeries: Bool {
        didSet {
            guard showsIPTVSeries != oldValue else { return }
            storeSetting(showsIPTVSeries, "library.iptvSeries")
            catalogSectionSwitched(.series, on: showsIPTVSeries)
        }
    }

    /// The IPTV group in the sidebar.
    var iptvSections: [LibrarySection] {
        LibrarySection.iptv.filter { ($0 != .movies || showsIPTVMovies) && ($0 != .series || showsIPTVSeries) }
    }

    private func storeSetting(_ value: Bool, _ key: String) {
        #if DEBUG
        if debugSettingsInMemory { return }
        #endif
        UserDefaults.standard.set(value, forKey: key)
    }

    @Published var nowPlaying: PlayItem? {
        didSet {
            if case .live(let id, _)? = nowPlaying?.kind, nowPlaying != oldValue {
                noteRecent(id)
                donateChannel(id)
            }
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
    /// A search to show in the library's toolbar search (Siri's "Suche … in Fernsy").
    @Published var requestedSearch: String?
    /// The tuner the player watches live TV through (shared with recordings of that channel).
    @Published private(set) var playerTuner: LiveTuner?
    /// The player window's engine while it is open (position and state for MCP `now_playing`).
    weak var playerEngine: PlayerEngine?
    /// The Jellyfin item that plays, for MCP (next episode and its countdown).
    weak var jellyfinPlayback: JellyfinPlayback?

    let epg = EPGStore()
    let tuners = TunerPool()
    let recorder = Recorder()
    /// The local MCP server (Settings › Assistenten); created after launch.
    private(set) lazy var mcp = MCPServer(app: self)
    #if DIRECT_DISTRIBUTION
    /// Sparkle updates of the DMG build ("Fernsy Direct" target only).
    private(set) var updater: Updater!
    #endif
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
        showAdultInRecent = UserDefaults.standard.bool(forKey: "library.showAdultInRecent")
        showsIPTVMovies = UserDefaults.standard.object(forKey: "library.iptvMovies") as? Bool ?? true
        showsIPTVSeries = UserDefaults.standard.object(forKey: "library.iptvSeries") as? Bool ?? true
        UserDefaults.standard.register(defaults: [Self.timeshiftMinutesKey: 60])
        recorder.app = self
        #if DIRECT_DISTRIBUTION
        updater = Updater(recorder: recorder)
        #endif
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
        Task { @MainActor in _ = self.mcp }
        startPathMonitor()
        loadSavedConnectionLimit()
        recorder.activate(accountKey: credentials?.accountKey)
        loadVisibility()
    }

    private func startPathMonitor() {
        #if DEBUG
        // IPTV_TESTNOPATH=1: as if macOS reported no network (the no-internet card).
        if ProcessInfo.processInfo.environment["IPTV_TESTNOPATH"] == "1" {
            isNetworkAvailable = false
            return
        }
        #endif
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isNetworkAvailable != available else { return }
                    AppLog.info(.network, available ? "network available" : "no network path")
                    self.isNetworkAvailable = available
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "app.path"))
    }

    func applyTimeshiftSetting() {
        tuners.keepSeconds = Double(UserDefaults.standard.integer(forKey: Self.timeshiftMinutesKey)) * 60
    }

    private func updateConnectionLimit() {
        var limit = max(1, account?.maxConnections ?? savedConnectionLimit ?? 1)
        var source = account?.maxConnections != nil ? "provider" : savedConnectionLimit != nil ? "saved" : "default"
        #if DEBUG
        if let forced = ProcessInfo.processInfo.environment["IPTV_MAXCONN"].flatMap(Int.init) { limit = forced; source = "IPTV_MAXCONN" }
        #endif
        guard limit != tuners.limit || source != connectionLimitSource else { return }
        connectionLimitSource = source
        AppLog.info(.app, "stream limit \(limit) (\(source))")
        guard limit != tuners.limit else { return }
        tuners.limit = limit
        recorder.rebalance()
    }

    private var connectionLimitSource = ""

    private var connectionLimitFile: URL? { cacheDirectory?.appendingPathComponent("connections.json") }

    private func loadSavedConnectionLimit() {
        savedConnectionLimit = connectionLimitFile.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Int.self, from: $0) }
        updateConnectionLimit()
    }

    private func saveConnectionLimit() {
        guard let limit = account?.maxConnections, limit != savedConnectionLimit, let file = connectionLimitFile,
              let data = try? JSONEncoder().encode(limit) else { return }
        try? data.write(to: file, options: .atomic)
        savedConnectionLimit = limit
    }

    /// Asks the provider for the account again (stream limit, expiry); a failed request keeps
    /// what is known.
    private func refreshAccount(_ client: XtreamClient) async {
        #if DEBUG
        // IPTV_TESTCATALOGFAIL=1 makes this fail too, as if the provider were unreachable.
        if ProcessInfo.processInfo.environment["IPTV_TESTCATALOGFAIL"] != nil { return }
        #endif
        if let info = try? await client.account() { account = info }
    }

    /// Development login from IPTV_SERVER/IPTV_USER/IPTV_PASS. Takes precedence over the
    /// keychain, which a freshly built debug binary may not read without a password prompt.
    private static var debugCredentials: XtreamCredentials? {
        #if DEBUG
        if let copied = XtreamCredentials.copied { return copied }
        let env = ProcessInfo.processInfo.environment
        guard let server = env["IPTV_SERVER"], let user = env["IPTV_USER"], let pass = env["IPTV_PASS"] else { return nil }
        return XtreamCredentials(server: server, username: user, password: pass)
        #else
        return nil
        #endif
    }

    #if DEBUG
    private var debugFavoritesInMemory = false
    private var debugSettingsInMemory = false
    private var debugAdultChannels: Set<Int> = []

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
        // IPTV_SECTION=<live|recordings|…>: the library opens on that section.
        if let section = env["IPTV_SECTION"].flatMap(LibrarySection.init(rawValue:)) {
            requestedSection = section
        }
        if let list = env["IPTV_TESTRECORD"] {
            // IPTV_TESTRECORD=<channel>:<starts in s>:<seconds>[:<before min>:<after min>],…: shows
            // recorded without padding, or with the given padding, planned in this order.
            let specs = list.split(separator: ",").map { $0.split(separator: ":").compactMap { Double($0) } }.filter { $0.count == 3 || $0.count == 5 }
            Task {
                while channels.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                let now = Date()
                for (n, spec) in specs.enumerated() {
                    guard let channel = channel(Int(spec[0])) else { continue }
                    let start = now.addingTimeInterval(spec[1])
                    let entry = EPGEntry(id: "test\(n)", title: "Test \(n + 1) \(Int(spec[0]))", description: "", start: start, end: start.addingTimeInterval(spec[2]))
                    recorder.schedule(entry, on: channel, padding: spec.count == 5 ? (spec[3] * 60, spec[4] * 60) : (0, 0))
                }
            }
        }
        if let spec = env["IPTV_TESTPADDING"]?.split(separator: ":").compactMap({ Double($0) }), spec.count == 3 {
            // IPTV_TESTPADDING=<after s>:<before min>:<after min>: as if Settings changed (without
            // touching the shared defaults of an installed Fernsy).
            DispatchQueue.main.asyncAfter(deadline: .now() + spec[0]) { [recorder] in
                recorder.applyPadding(before: spec[1] * 60, after: spec[2] * 60)
            }
        }
        // Youth protection tests, in memory only (the demo has no adult channels):
        // IPTV_TESTADULT=<id,…> treats channels as adult, IPTV_RECENT=<id,…> sets "Zuletzt
        // gesehen", IPTV_SHOWADULT / IPTV_ADULTRECENT=0|1 set both settings,
        // IPTV_TESTUNRECENT=<id> removes a channel from the history 3 s after the catalog loaded.
        if let list = env["IPTV_TESTADULT"] { debugAdultChannels = Set(list.split(separator: ",").compactMap { Int($0) }) }
        if let list = env["IPTV_RECENT"] { recentChannels = list.split(separator: ",").compactMap { Int($0) } }
        // IPTV_SHOWMOVIES / IPTV_SHOWSERIES=0|1: the IPTV account's films and series, in memory only.
        if env["IPTV_SHOWMOVIES"] != nil || env["IPTV_SHOWSERIES"] != nil {
            debugSettingsInMemory = true
            if let value = env["IPTV_SHOWMOVIES"] { showsIPTVMovies = value == "1" }
            if let value = env["IPTV_SHOWSERIES"] { showsIPTVSeries = value == "1" }
        }
        // IPTV_TESTINTENT=<step>[|<step>…]: runs Siri's actions once the catalog is loaded, as the
        // system does, one step every 4 s, and logs the answer. Steps: query:<text>, play:<id>,
        // whatson, find:<text>, record[:<id>], recordshow:<channel>:<epoch>, stop.
        if let steps = env["IPTV_TESTINTENT"]?.split(separator: "|").map(String.init) {
            Task {
                while channels.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                try? await Task.sleep(for: .seconds(2))
                for step in steps {
                    let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
                    let arg = parts.count > 1 ? parts[1] : ""
                    var line: String
                    switch parts[0] {
                    case "query":
                        let found = (try? await ChannelQuery().entities(matching: arg)) ?? []
                        line = found.map { "\($0.id) \($0.name)" }.joined(separator: ", ")
                    case "suggested":
                        line = ((try? await ChannelQuery().suggestedEntities()) ?? []).map(\.name).joined(separator: ", ")
                    case "play": line = await IntentActions.play(channelId: Int(arg) ?? 0).text
                    case "whatson":
                        let answer = await IntentActions.whatsOn()
                        line = answer.text + " | rows: \(answer.rows.count)"
                    case "find":
                        let answer = await IntentActions.findShow(arg)
                        line = answer.text + " | shows: " + answer.shows.prefix(3).map(\.id).joined(separator: ",")
                    case "record": line = await IntentActions.recordNow(channelId: Int(arg)).text
                    case "recordshow": line = await IntentActions.record(showId: arg).text
                    case "stop": line = await IntentActions.stop().text
                    case "open": line = await IntentActions.play(channelId: Int(arg) ?? 0).text
                    case "search": line = IntentActions.search(arg).text
                    default: line = "unknown step"
                    }
                    debugLog("[test] intent \(step): \(line)")
                    try? await Task.sleep(for: .seconds(4))
                }
            }
        }
        // IPTV_TESTSWITCHMEDIA=<s>:<movies|series>:<0|1>,…: flips the switch s seconds after the
        // live catalog loaded, as in Settings (also in memory only).
        if let list = env["IPTV_TESTSWITCHMEDIA"] {
            debugSettingsInMemory = true
            let steps = list.split(separator: ",").map { $0.split(separator: ":") }.filter { $0.count == 3 }
            Task {
                while channels.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                let loaded = Date()
                for step in steps {
                    guard let at = Double(step[0]) else { continue }
                    try? await Task.sleep(for: .seconds(max(0, at - Date().timeIntervalSince(loaded))))
                    debugLog("[test] \(step[1]) \(step[2] == "1" ? "on" : "off")")
                    if step[1] == "movies" { showsIPTVMovies = step[2] == "1" } else { showsIPTVSeries = step[2] == "1" }
                }
            }
        }
        if env["IPTV_SHOWADULT"] != nil || env["IPTV_ADULTRECENT"] != nil {
            debugSettingsInMemory = true
            if let value = env["IPTV_SHOWADULT"] { showAdult = value == "1" }
            if let value = env["IPTV_ADULTRECENT"] { showAdultInRecent = value == "1" }
        }
        if let id = env["IPTV_TESTUNRECENT"].flatMap(Int.init) {
            Task {
                while channels.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                try? await Task.sleep(for: .seconds(3))
                removeRecent(id)
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
        if env["IPTV_PLANTEST"] == "1" { RecordingPlan.selfTest() }
        if let keys = env["IPTV_TESTWATCHED"] { markWatchedForTest(keys.split(separator: ",").map(String.init)) }
        if let spec = env["IPTV_TESTRESUME"] {
            // IPTV_TESTRESUME=<key>:<position s>:<duration s>,…: resume positions for this run.
            for item in spec.split(separator: ",") {
                let p = item.split(separator: ":")
                if p.count == 3, let position = Double(p[1]), let duration = Double(p[2]) {
                    testResume[String(p[0])] = (position, duration)
                }
            }
        }
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
        SiriIndex.clear()
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
        #if DEBUG
        // A copied account is shown from its cache only: no credentials, no requests.
        if client.credentials.isCopied { return }
        #endif
        if account == nil {
            Task { await refreshAccount(client) }
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
            if showsIPTVMovies { group.addTask { await Self.decode(.movies, from: dir) } }
            if showsIPTVSeries { group.addTask { await Self.decode(.series, from: dir) } }
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

        // The package may have changed (stream limit).
        Task { await refreshAccount(client) }
        let started = Date()
        do {
            #if DEBUG
            // IPTV_TESTCATALOGFAIL=1: the refresh fails as if the provider were unreachable.
            if ProcessInfo.processInfo.environment["IPTV_TESTCATALOGFAIL"] != nil { throw URLError(.cannotConnectToHost) }
            #endif
            // Download everything, keep only actions whose payload changed.
            let changed: Set<CatalogAction> = try await withThrowingTaskGroup(of: CatalogAction?.self) { group in
                for action in CatalogSection.allCases.filter(isEnabled).flatMap(\.actions) {
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

            for section in CatalogSection.allCases where isEnabled(section) && (!changed.isDisjoint(with: section.actions) || isEmpty(section)) {
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

    private func isEnabled(_ section: CatalogSection) -> Bool {
        switch section {
        case .live: return true
        case .movies: return showsIPTVMovies
        case .series: return showsIPTVSeries
        }
    }

    /// Off: the section is emptied and its cache removed. On: it is downloaded at once, after a
    /// refresh that is still running (which skipped it).
    private func catalogSectionSwitched(_ section: CatalogSection, on: Bool) {
        AppLog.info(.catalog, "\(section == .movies ? "films" : "series") switched \(on ? "on" : "off")")
        guard on else {
            apply(section == .movies ? .movies([], []) : .series([], []))
            if let dir = cacheDirectory {
                for action in section.actions { try? FileManager.default.removeItem(at: dir.appendingPathComponent(action.rawValue + ".json")) }
            }
            return
        }
        Task {
            while refreshInFlight { try? await Task.sleep(for: .milliseconds(200)) }
            guard isEnabled(section), let client, let dir = cacheDirectory else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                for action in section.actions {
                    try await client.catalog(action).write(to: dir.appendingPathComponent(action.rawValue + ".json"), options: .atomic)
                }
                if isEnabled(section), let decoded = await Self.decode(section, from: dir) { apply(decoded) }
                AppLog.info(.catalog, "\(section == .movies ? "films" : "series") downloaded")
            } catch {
                refreshError = error.localizedDescription
                AppLog.error(.catalog, "download after switching on failed: \(error.localizedDescription)")
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

    /// Marked as adult by the provider, or in a category detected as adult
    /// (`adultCategories`: the ids of those live categories).
    func isAdult(_ channel: LiveChannel, adultCategories: Set<String>) -> Bool {
        #if DEBUG
        if debugAdultChannels.contains(channel.id) { return true }
        #endif
        return channel.isAdult || adultCategories.contains(channel.categoryId ?? "")
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
        SiriIndex.schedule(self)
    }

    /// Teaches Siri which channels are watched (suggestions, "Schalte Fernsy auf …").
    private func donateChannel(_ id: Int) {
        guard SiriIndex.isEnabled, let channel = channel(id) else { return }
        let entity = ChannelEntity(channel, app: self)
        Task { _ = try? await PlayChannelIntent(channel: entity).donate() }
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

    /// Context menu: takes a channel out of "Zuletzt gesehen".
    func removeRecent(_ channelId: Int) {
        recentChannels.removeAll { $0 == channelId }
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
    func recordingsBlocking(_ channelId: Int) -> [Recording] {
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
        if Self.skipKeychain { return testResume[key]?.position ?? 0 }
        return UserDefaults.standard.double(forKey: "resume." + key)
    }

    private var testResume: [String: (position: Double, duration: Double)] = [:]
    private var testWatched: Set<String> = []

    func saveResume(_ key: String, position: Double, duration: Double) {
        let finished = duration > 0 && position > duration - 90
        // Test runs (no keychain) share the installed app's defaults: they keep this in memory.
        if Self.skipKeychain {
            testResume[key] = position < 30 || finished ? nil : (position, duration)
            if finished { testWatched.insert(key) }
            objectWillChange.send()
            return
        }
        if position < 30 || finished {
            UserDefaults.standard.removeObject(forKey: "resume." + key)
            UserDefaults.standard.removeObject(forKey: "resume." + key + ".duration")
        } else {
            UserDefaults.standard.set(position, forKey: "resume." + key)
            if duration > 0 { UserDefaults.standard.set(duration, forKey: "resume." + key + ".duration") }
        }
        if finished {
            UserDefaults.standard.set(true, forKey: "watched." + key)
            AppLog.detail(.player, "watched \(key)")
        }
        objectWillChange.send()
    }

    /// 0…1 of a started item, nil without a stored duration.
    func resumeFraction(_ key: String) -> Double? {
        let position = resumePosition(key)
        let duration = Self.skipKeychain ? (testResume[key]?.duration ?? 0)
            : UserDefaults.standard.double(forKey: "resume." + key + ".duration")
        guard position > 0, duration > 0 else { return nil }
        return min(1, position / duration)
    }

    /// Played to its end (within the last 90 s) at some point.
    func isWatched(_ key: String) -> Bool {
        Self.skipKeychain ? testWatched.contains(key) : UserDefaults.standard.bool(forKey: "watched." + key)
    }

    #if DEBUG
    /// IPTV_TESTWATCHED=<key>,…: these items count as watched (in memory).
    func markWatchedForTest(_ keys: [String]) { testWatched.formUnion(keys) }
    #endif
}
