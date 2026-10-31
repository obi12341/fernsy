import Combine
import FernsyCore
import FernsyPlayer
import Foundation
import Network
import SwiftUI

enum LibrarySection: String, Hashable, CaseIterable, Identifiable {
    /// Start across both accounts (mac-start-pages), above the groups.
    case start
    case live, movies, series, favorites, recordings
    case jellyfinHome, jellyfinFilms, jellyfinSeries
    var id: String { rawValue }

    /// Sections of the IPTV account and of the Jellyfin account (sidebar groups).
    static let iptv: [LibrarySection] = [.live, .movies, .series, .favorites, .recordings]
    static let jellyfin: [LibrarySection] = [.jellyfinHome, .jellyfinFilms, .jellyfinSeries]

    var isJellyfin: Bool { Self.jellyfin.contains(self) }

    var title: String {
        switch self {
        case .start: return String(localized: "Start")
        case .live: return String(localized: "Live TV")
        case .movies: return String(localized: "Movies")
        case .series: return String(localized: "Series")
        case .favorites: return String(localized: "Favorites")
        case .recordings: return String(localized: "Recordings")
        case .jellyfinHome: return String(localized: "Overview")
        case .jellyfinFilms: return String(localized: "Movies")
        case .jellyfinSeries: return String(localized: "Series")
        }
    }

    var icon: String {
        switch self {
        case .start: return "house"
        case .live: return "dot.radiowaves.left.and.right"
        case .movies: return "film"
        case .series: return "tv"
        case .favorites: return "star"
        case .recordings: return "record.circle"
        case .jellyfinHome: return "square.grid.2x2"
        case .jellyfinFilms: return "film"
        case .jellyfinSeries: return "tv"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var credentials: XtreamCredentials? {
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

    @Published var liveCategories: [XCategory] = []
    @Published var movieCategories: [XCategory] = []
    @Published var seriesCategories: [XCategory] = []
    @Published var channels: [LiveChannel] = []
    @Published var movies: [Movie] = []
    @Published var series: [Series] = []

    @Published var isLoading = false
    @Published var loadError: String?
    /// The last background refresh failed while the cached catalog is shown (Live TV's notice).
    @Published var refreshError: String?
    @Published var lastUpdated: Date?

    @Published var favorites: Set<String>
    /// Live channels played last, newest first (Live TV › "Zuletzt gesehen").
    @Published var recentChannels: [Int]
    /// Channels the provider reported offline when played in this run (cleared by a successful start).
    @Published var offlineChannels: Set<Int> = []
    /// macOS has a network path (Wi-Fi, Ethernet …). False lets the player say "no internet"
    /// instead of naming the provider.
    @Published private(set) var isNetworkAvailable = true
    private let pathMonitor = NWPathMonitor()
    static let recentLimit = LiveRules.recentLimit
    /// Hidden live categories and channels of the signed-in account.
    @Published var visibility = ChannelVisibility() {
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
            storeSetting(showsIPTVMovies, LibraryRules.moviesSwitchKey)
            catalogSectionSwitched(.movies, on: showsIPTVMovies)
        }
    }
    @Published var showsIPTVSeries: Bool {
        didSet {
            guard showsIPTVSeries != oldValue else { return }
            storeSetting(showsIPTVSeries, LibraryRules.seriesSwitchKey)
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
            // An archive holds its own connection while it plays (catch-up design 4).
            if case .archive(let id, _, _)? = oldValue?.kind, nowPlaying != oldValue { tuners.releaseArchive(id) }
            if case .archive(let id, _, _)? = nowPlaying?.kind { tuners.reserveArchive(id) }
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
    /// Fernsy Cloud (add-recording-cloud): subscription, account, cloud recordings, uploads.
    let cloud = CloudModel()
    private(set) lazy var cloudUploads = CloudUploadQueue(api: cloud.client, keys: cloud.keys, stateURL: CloudUploadQueue.defaultStateURL())
    var cloudRecordingWatch: AnyCancellable?
    /// Recordings the automatic upload has seen finish (each is queued at most once).
    var cloudAutoQueued: Set<UUID> = []
    /// Held against idle sleep for recordings (`keepAwake(reason:)`).
    var recordingActivity: NSObjectProtocol?
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

    // iCloud sync (icloud-sync, FernsyCore SyncStore and LoginSync): settings and choices in
    // the key-value store, logins in CloudKit. Keychain-less runs sync only with IPTV_SYNC=1.
    let sync = SyncStore(backing: AppModel.syncAllowed ? NSUbiquitousKeyValueStore.default : nil, keys: AppModel.syncedKeys)
    let logins = AppModel.makeLogins()
    /// Logins found in iCloud while this Mac has none: the login screen offers them.
    @Published var syncedXtream: XtreamCredentials?
    @Published var syncedJellyfin: LoginSync.JellyfinLogin?
    @Published var iCloudAvailable = false
    /// Launched without an account while logins may be in iCloud: "Signing in …" shows until
    /// they are tried (icloud-auto-signin); then why none worked, if so.
    @Published var signingInFromICloud = false
    /// The launch screen's lines while `signingInFromICloud`.
    @Published var iCloudSteps: [ICloudSignInStep] = []
    @Published var iCloudSignInError: String?

    static let timeshiftMinutesKey = "timeshift.minutes"

    var channelsByCategory: [String: [LiveChannel]] = [:]
    var moviesByCategory: [String: [Movie]] = [:]
    var seriesByCategory: [String: [Series]] = [:]
    /// Live channels per category and in total, without hidden ones.
    var visibleChannelCounts: [String: Int] = [:]
    var visibleChannelTotal = 0

    private var logSecrets: Set<AnyCancellable> = []

    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: LiveRules.favoritesKey) ?? [])
        recentChannels = Self.skipKeychain ? [] : (UserDefaults.standard.array(forKey: LiveRules.recentKey) as? [Int] ?? [])
        showAdult = UserDefaults.standard.bool(forKey: "library.showAdult")
        showAdultInRecent = UserDefaults.standard.bool(forKey: "library.showAdultInRecent")
        showsIPTVMovies = UserDefaults.standard.object(forKey: LibraryRules.moviesSwitchKey) as? Bool ?? true
        showsIPTVSeries = UserDefaults.standard.object(forKey: LibraryRules.seriesSwitchKey) as? Bool ?? true
        UserDefaults.standard.register(defaults: [Self.timeshiftMinutesKey: 60])
        #if DEBUG
        JellyfinClient.deviceName = (Host.current().localizedName ?? "Mac") + " (Debug)"
        #else
        JellyfinClient.deviceName = Host.current().localizedName ?? "Mac"
        #endif
        recorder.host = self
        Recorder.registerMacDefaults()
        recorder.keepAwakePolicy = Recorder.macKeepAwakePolicy
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
        if credentials == nil && jellyfin.session == nil && logins.isActive { signingInFromICloud = true }
        startSync()
        startCloud()
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
    func refreshAccount(_ client: XtreamClient) async {
        #if DEBUG
        // IPTV_TESTCATALOGFAIL=1 makes this fail too, as if the provider were unreachable.
        if ProcessInfo.processInfo.environment["IPTV_TESTCATALOGFAIL"] != nil { return }
        #endif
        if let info = try? await client.account() { account = info }
    }

    /// Development login from IPTV_SERVER/IPTV_USER/IPTV_PASS. Takes precedence over the
    /// keychain, which a freshly built debug binary may not read without a password prompt.
    static var debugCredentials: XtreamCredentials? {
        #if DEBUG
        if let copied = XtreamCredentials.copied { return copied }
        let env = ProcessInfo.processInfo.environment
        // An empty IPTV_SERVER= starts without an account, as on Apple TV.
        guard let server = env["IPTV_SERVER"], !server.isEmpty, let user = env["IPTV_USER"], let pass = env["IPTV_PASS"] else { return nil }
        return XtreamCredentials(server: server, username: user, password: pass)
        #else
        return nil
        #endif
    }

    var client: XtreamClient? { credentials.map(XtreamClient.init) }

    // Stored state of the extensions.
    #if DEBUG
    var debugFavoritesInMemory = false
    var debugSettingsInMemory = false
    var debugAdultChannels: Set<Int> = []
    #endif
    var lastRefresh: Date?
    var refreshInFlight = false
    var periodicRefresh: Task<Void, Never>?

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
        syncedXtream = nil
        Task { await logins.save(creds) }
        epg.removeAll()
        credentials = creds
        account = info
        if signingInFromICloud { iCloudSteps.finish(.provider, then: ICloudSignInStep(.channels)) }
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

    // MARK: Adult filter

    func isAdultCategory(_ category: XCategory) -> Bool { LiveRules.isAdultCategory(category) }

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
                title: String(localized: "Recording in Progress"),
                message: String(localized: "“\(first.title)” is being recorded on \(first.channelName). Your account allows only \(tuners.limit) stream(s) at a time. Stop the recording and switch to \(channel.displayName)?"),
                confirm: String(localized: "Stop Recording and Switch"), cancel: String(localized: "Cancel"))
            guard accepted else { return }
            for recording in blocking { recorder.stop(recording.id) }
            nowPlaying = item
        }
    }

    /// A past show from the channel's archive (catch-up): asks first when recordings hold every
    /// connection, as switching channels does.
    func playArchive(_ show: EPGEntry, on channel: LiveChannel) {
        guard Archive.isPlayable(show, on: channel),
              let url = client?.archiveURL(channel: channel.id, start: show.start, minutes: Archive.minutes(for: show), timeZone: account?.serverTimeZone)
        else { return }
        let item = PlayItem(kind: .archive(channelId: channel.id, start: show.start, end: show.end), title: show.title,
                            subtitle: "\(channel.displayName) · \(show.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))",
                            url: url)
        let blocking = recorder.recordings.filter { r in
            r.status == .recording && tuners.archiveBlockers().contains { $0.owners.contains(.recording(r.id)) }
        }
        guard let first = blocking.first else {
            nowPlaying = item
            return
        }
        Task {
            let accepted = await Prompt.ask(
                title: String(localized: "Recording in Progress"),
                message: String(localized: "“\(first.title)” is being recorded on \(first.channelName). Your account allows only \(tuners.limit) stream(s) at a time. Stop the recording and play “\(show.title)” from the archive?"),
                confirm: String(localized: "Stop Recording and Play"), cancel: String(localized: "Cancel"))
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
        LiveRules.zapOrder(category: categoryId.flatMap { channelsByCategory[$0] }, all: channels, isHidden: isHidden)
    }

    /// The visible channels the player zaps through.
    func zapList(categoryId: String?) -> [LiveChannel] {
        zapOrder(categoryId: categoryId).filter { !isHidden($0) }
    }

    /// The visible channel `offset` steps away from `channelId` (wrapping), with its 1-based
    /// number. From a hidden channel it steps to the visible ones around its place.
    func neighbor(of channelId: Int, categoryId: String?, offset: Int) -> (channel: LiveChannel, number: Int)? {
        LiveRules.neighbor(of: channelId, in: zapOrder(categoryId: categoryId), offset: offset, isHidden: isHidden)
    }

    func channel(_ id: Int) -> LiveChannel? {
        channels.first { $0.id == id }
    }

    // MARK: Start

    /// Series details loaded on their pages, so Start can name started episodes (mac-start-pages;
    /// the Apple TV keeps them the same way).
    var seriesInfos: [Int: SeriesInfo] = [:]

    /// Episodes of loaded series by id, for Start's Continue Watching.
    var episodeIndex: [String: (Episode, Series)] {
        var index: [String: (Episode, Series)] = [:]
        for (id, info) in seriesInfos {
            guard let show = series.first(where: { $0.id == id }) else { continue }
            for episode in info.seasons.values.flatMap({ $0 }) { index[episode.id] = (episode, show) }
        }
        return index
    }

    // MARK: Resume positions

    /// Resume positions and watched marks (FernsyCore). Test runs (no keychain) share the
    /// installed app's defaults, so they keep them in memory.
    lazy var resume = ResumeStore(defaults: Self.skipKeychain ? nil : .standard)

    func resumePosition(_ key: String) -> Double { resume.position(key) }

    /// Counts changes of resume positions (played here or arrived from iCloud), so Start rebuilds
    /// Continue Watching without reading every position on each redraw.
    @Published var resumeRevision = 0

    func saveResume(_ key: String, position: Double, duration: Double) {
        if resume.save(key, position: position, duration: duration) { AppLog.detail(.player, "watched \(key)") }
        resumeRevision += 1
    }

    /// 0…1 of a started item, nil without a stored duration.
    func resumeFraction(_ key: String) -> Double? { resume.fraction(key) }

    /// Played to its end (within the last 90 s) at some point.
    func isWatched(_ key: String) -> Bool { resume.isWatched(key) }

    #if DEBUG
    /// IPTV_TESTWATCHED=<key>,…: these items count as watched (in memory).
    func markWatchedForTest(_ keys: [String]) { resume.markWatched(keys) }
    #endif
}
