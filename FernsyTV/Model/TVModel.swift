import Combine
import FernsyCore
import FernsyPlayer
import Foundation
import Network
import UIKit

/// Everything the Apple TV screens read: the account, the live catalog with its guide, and
/// playback. Screens call only this; the provider, guide and playback logic come from
/// FernsyCore and FernsyPlayer, as in the Mac app.
@MainActor
final class TVModel: ObservableObject {
    enum SignIn: Equatable {
        case signedOut
        case signingIn
        case signedIn
        case failed(String)
        /// iPad and iPhone: the stored account could not be checked for lack of a connection; the
        /// tabs show what is cached and it is tried again when the network returns
        /// (offline-recording-downloads design F).
        case offline
    }

    @Published private(set) var signIn: SignIn = .signedOut
    @Published private(set) var credentials: XtreamCredentials?
    @Published private(set) var maxConnections = 1
    /// The provider server's time zone, for archive requests (catch-up design 2).
    private(set) var serverTimeZone: TimeZone?
    @Published private(set) var categories: [XCategory] = [] {
        didSet { adultCategoryIDs = Set(categories.filter(LiveRules.isAdultCategory).map(\.id)) }
    }
    /// Kept with `categories`: every visible-channel filter asks it once per channel, and with
    /// 12,000 channels and 300 categories working it out per call froze Live TV.
    private(set) var adultCategoryIDs: Set<String> = []
    @Published private(set) var channels: [LiveChannel] = []
    /// The live channel in the player, nil when the player is closed.
    @Published private(set) var playing: LiveChannel?
    /// The channel playing in Live TV's pane (muted unless its sound was turned on), sharing the
    /// player's engine and connection, so clicking it continues full screen (design E).
    @Published private(set) var previewing: LiveChannel?
    private var previewSound = false
    /// The recording in the player (TVModel+Recordings.swift), nil when none plays.
    @Published var playingRecording: Recording?

    // Films and series (TVModel+Library.swift).
    @Published var movieCategories: [XCategory] = []
    @Published var movies: [Movie] = [] {
        didSet {
            moviesByID = Dictionary(movies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            newestMovies = Array(movies.sorted { $0.added > $1.added }.prefix(12))
        }
    }
    @Published var seriesCategories: [XCategory] = []
    @Published var series: [Series] = [] {
        didSet {
            seriesByID = Dictionary(series.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            newestSeries = Array(series.sorted { $0.lastModified > $1.lastModified }.prefix(8))
        }
    }
    /// Kept with the lists (tvos-start-scrolling): Start looks items up by id and takes the
    /// newest without sorting 30,000 films per call.
    private(set) var moviesByID: [Int: Movie] = [:]
    private(set) var seriesByID: [Int: Series] = [:]
    private(set) var newestMovies: [Movie] = []
    private(set) var newestSeries: [Series] = []
    /// Bumped when resume positions arrive from another device: Start rebuilds Continue Watching.
    @Published var resumeRevision = 0
    @Published var movieInfo: [Int: MovieDetails] = [:]
    @Published var seriesInfo: [Int: SeriesInfo] = [:]
    /// The provider's films and series (Settings › IPTV Account), app-wide with the Mac's keys
    /// and synced (tvos-vod-switch). Off: neither downloaded, cached nor shown; favourites and
    /// resume positions stay.
    @Published var showsIPTVMovies = TVModel.librarySwitch(LibraryRules.moviesSwitchKey, env: "IPTV_SHOWMOVIES") {
        didSet {
            guard showsIPTVMovies != oldValue else { return }
            storeLibrarySwitch(showsIPTVMovies, LibraryRules.moviesSwitchKey)
            librarySwitched(movies: true, on: showsIPTVMovies)
        }
    }
    @Published var showsIPTVSeries = TVModel.librarySwitch(LibraryRules.seriesSwitchKey, env: "IPTV_SHOWSERIES") {
        didSet {
            guard showsIPTVSeries != oldValue else { return }
            storeLibrarySwitch(showsIPTVSeries, LibraryRules.seriesSwitchKey)
            librarySwitched(movies: false, on: showsIPTVSeries)
        }
    }
    /// A film and series download is running; switching a kind on waits for it.
    var libraryLoading = false
    /// The film, episode or Jellyfin item in the player, nil when none plays.
    @Published var playingVOD: VODItem?
    /// Fernsy Cloud (add-recording-cloud): subscription, account and cloud recordings.
    let cloud = CloudModel()
    #if os(iOS)
    /// Downloaded cloud recordings (offline-recording-downloads), iPad and iPhone only.
    private(set) lazy var downloads: CloudDownloads? = CloudFeature.isEnabled ? CloudDownloads.live(client: cloud.client, keys: cloud.keys) : nil
    #endif
    var jellyfinPlayback: JellyfinPlayback?
    var archivePlayback: ArchivePlayback?
    /// Resume positions and watched marks with the Mac's keys; test runs keep them in memory.
    let resume = ResumeStore(defaults: TVModel.skipKeychain ? nil : .standard)
    /// Where the playing channel was started from: the player's channel strip zaps through it.
    var zapSource: LiveSource = .all
    /// The engine's mute state outside the preview (debug builds start muted).
    private var baseMuted = false
    /// Launched with stored credentials: the sign-in at launch shows progress, not the welcome screen.
    private(set) var startedWithAccount = false

    // Live lists, as on the Mac (LiveRules); see TVModel+Live.swift.
    @Published var favorites: Set<String> = []
    @Published var recentChannels: [Int] = []
    @Published var visibility = ChannelVisibility()
    @Published var pinned = PinnedCategories()
    /// Live TV's source as chosen in the category column (`liveSource` resolves it) and its
    /// view, for the signed-in account (tvos-live-and-guide).
    @Published var chosenLiveSource: LiveSource?
    @Published var liveView: LiveView = .list { didSet { storeLive(liveView.rawValue, as: "live.view") } }

    // iCloud sync (icloud-sync, FernsyCore SyncStore and LoginSync; TVModel+Sync.swift).
    let sync = SyncStore(backing: TVModel.syncAllowed ? NSUbiquitousKeyValueStore.default : nil, keys: TVModel.syncedKeys)
    let logins = TVModel.makeLogins()
    /// Logins found in iCloud while this Apple TV has none: the welcome screen offers them.
    @Published var syncedXtream: XtreamCredentials?
    @Published var syncedJellyfin: LoginSync.JellyfinLogin?
    @Published var iCloudAvailable = false
    /// Launched without an account while logins may be in iCloud: "Anmelden …" shows until they
    /// are tried (icloud-auto-signin); then why none worked, if so.
    @Published var signingInFromICloud = false
    /// The launch screen's lines while `signingInFromICloud`.
    @Published var iCloudSteps: [ICloudSignInStep] = []
    @Published var iCloudSignInError: String?

    let engine = PlayerEngine()
    /// Whether the Apple TV has a network path; the player names it as the cause of a stall
    /// (tvos-player-status design 4, as `AppModel.isNetworkAvailable` on the Mac).
    @Published private(set) var isNetworkAvailable = true
    private let pathMonitor = NWPathMonitor()
    let guide = EPGStore()
    let tuners = TunerPool()
    let recorder = Recorder()
    /// The Jellyfin account (FernsyCore), as on the Mac; created after its device name is set.
    let jellyfin: JellyfinStore
    /// A question of the recorder, shown as an alert (TVModel+Recordings.swift).
    @Published var question: RecorderQuestion?
    /// A message about a recording just planned (refused, or padding shortened).
    @Published var notice: String?
    private(set) var client: XtreamClient?

    static let shared = TVModel()

    /// Timeshift buffer on Apple TV: Caches, which tvOS may need back (design F).
    static let timeshiftSeconds: Double = 30 * 60

    private var recorderChanges: AnyCancellable?
    private var jellyfinChanges: AnyCancellable?

    private init() {
        #if DEBUG
        TestOffline.installShared()
        // IPTV_FRESHCATALOG=1: start with empty Caches, as after iOS cleared them (catalog,
        // guide, artwork, cloud details); downloads in Application Support stay.
        if ProcessInfo.processInfo.environment["IPTV_FRESHCATALOG"] == "1" {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            for item in (try? FileManager.default.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: item)
            }
        }
        #endif
        // The server lists this Apple TV by its name; debug builds are a device of their own.
        #if DEBUG
        JellyfinClient.deviceName = UIDevice.current.name + " (Debug)"
        #else
        JellyfinClient.deviceName = UIDevice.current.name
        #endif
        JellyfinStore.cacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        jellyfin = JellyfinStore(skipKeychain: Self.skipKeychain)
        tuners.keepSeconds = Self.timeshiftSeconds
        recorder.host = self
        #if os(iOS)
        cloud.downloads = downloads
        #endif
        #if DEBUG
        // IPTV_TESTRESUME=<key>:<position s>:<duration s>,…: resume positions for this run, as on
        // the Mac (keys such as movie.500, episode.<id>).
        if let spec = ProcessInfo.processInfo.environment["IPTV_TESTRESUME"] {
            for item in spec.split(separator: ",") {
                let p = item.split(separator: ":")
                if p.count == 3, let position = Double(p[1]), let duration = Double(p[2]) {
                    resume.save(String(p[0]), position: position, duration: duration)
                }
            }
        }
        #endif
        // Screens observe the model: the recorder's list changes are the model's changes too.
        recorderChanges = recorder.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        jellyfinChanges = jellyfin.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        if let credentials = Self.debugCredentials ?? (Self.skipKeychain ? nil : CredentialStore.load()) {
            startedWithAccount = true
            Task { await signIn(credentials, remember: false) }
        } else if jellyfin.session == nil && logins.isActive {
            signingInFromICloud = true
        }
        startSync()
        if CloudFeature.isEnabled { Task { await cloud.start() } }
        #if os(iOS)
        if let downloads { Task { await downloads.resume() } }
        #endif
        startPathMonitor()
        #if DEBUG
        if ProcessInfo.processInfo.environment["IPTV_FRAMESTATS"] == "1" { FrameStats.shared.start() }
        #endif
    }

    private func startPathMonitor() {
        #if DEBUG
        // IPTV_TESTNOPATH=1: as if the Apple TV had no network (the no-internet card).
        if ProcessInfo.processInfo.environment["IPTV_TESTNOPATH"] == "1" {
            isNetworkAvailable = false
            return
        }
        // IPTV_TESTOFFLINE=1: no network until the MCP tool `set_offline` ends it.
        if TestOffline.isOn {
            isNetworkAvailable = false
            return
        }
        #endif
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.networkChanged(available) }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "tv.path"))
    }

    func networkChanged(_ available: Bool) {
        guard isNetworkAvailable != available else { return }
        AppLog.info(.network, available ? "network available" : "no network path")
        isNetworkAvailable = available
        guard available else { return }
        #if os(iOS)
        // Opened without a connection: sign in now, and go on with interrupted downloads.
        if signIn == .offline, let credentials { Task { await signIn(credentials, remember: false) } }
        if let downloads { Task { await downloads.resume() } }
        if CloudFeature.isEnabled { Task { await cloud.refresh() } }
        #endif
    }

    /// No connection, as opposed to a server that answers with an error.
    static func isConnectionFailure(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
                .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff].contains(error.code)
    }

    // MARK: Account

    func signIn(_ credentials: XtreamCredentials, remember: Bool = true) async {
        signIn = .signingIn
        let client = XtreamClient(credentials: credentials)
        // Restoring the stored account (`remember` false): the cached catalog shows at once and the
        // server's answer replaces it. A new sign-in shows nothing before the server accepts it.
        if !remember, let cached = CatalogCache.load(accountKey: credentials.accountKey) {
            // The rows load their guide as they appear, so they need the client already.
            self.client = client
            self.credentials = credentials
            loadLiveState()
            apply(cached)
        }
        do {
            let account = try await client.account()
            self.client = client
            self.credentials = credentials
            maxConnections = max(1, account.maxConnections ?? 1)
            serverTimeZone = account.serverTimeZone
            if let zone = account.serverTimeZone { AppLog.detail(.app, "server time zone \(zone.identifier)") }
            #if DEBUG
            // IPTV_MAXCONN=<n>: the account's stream limit for this run (single-stream tests).
            if let value = ProcessInfo.processInfo.environment["IPTV_MAXCONN"].flatMap(Int.init) { maxConnections = max(1, value) }
            #endif
            tuners.limit = maxConnections
            if remember && !Self.skipKeychain { CredentialStore.save(credentials) }
            // To iCloud: a new login, or a stored one from before sync that iCloud lacks.
            syncedXtream = nil
            Task {
                if remember { await logins.save(credentials) } else if await logins.xtream() == nil { await logins.save(credentials) }
            }
            loadLiveState()
            #if DEBUG
            // IPTV_TESTHIDE=category:<id>,channel:<id>,…: hidden for this run (in memory), as on the Mac.
            if let spec = ProcessInfo.processInfo.environment["IPTV_TESTHIDE"] {
                for item in spec.split(separator: ",") {
                    let p = item.split(separator: ":")
                    guard p.count == 2 else { continue }
                    if p[0] == "category" { visibility.hiddenCategories.insert(String(p[1])) }
                    if p[0] == "channel", let id = Int(p[1]) { visibility.hiddenChannels.insert(id) }
                }
            }
            // IPTV_FRESHRECORDINGS=1: start without the recordings of earlier test runs.
            if ProcessInfo.processInfo.environment["IPTV_FRESHRECORDINGS"] == "1" {
                try? FileManager.default.removeItem(at: Self.recordingsDirectory(accountKey: credentials.accountKey))
            }
            #endif
            recorder.activate(accountKey: credentials.accountKey)
            signIn = .signedIn
            if signingInFromICloud { iCloudSteps.finish(.provider, then: ICloudSignInStep(.channels)) }
            AppLog.info(.app, "signed in, \(maxConnections) stream(s)")
            try await loadCatalog()
            Task { await loadLibraryCatalog() }
            #if DEBUG
            autoplay()
            testRecord()
            #endif
        } catch {
            #if os(iOS)
            // The stored account without a connection: keep it and open the tabs anyway (design F).
            if !remember, Self.isConnectionFailure(error) || !isNetworkAvailable {
                self.client = client
                self.credentials = credentials
                loadLiveState()
                signIn = .offline
                AppLog.warning(.catalog, "no connection, opened with \(channels.count) cached channels: \(error.localizedDescription)")
                return
            }
            #endif
            signIn = channels.isEmpty ? .failed(error.localizedDescription) : .signedIn
            AppLog.error(.catalog, "sign-in or catalog failed: \(error.localizedDescription)")
        }
    }

    func signOut() {
        stop()
        recorder.activate(accountKey: nil)
        if !Self.skipKeychain { CredentialStore.delete() }
        client = nil
        credentials = nil
        categories = []
        channels = []
        signIn = .signedOut
        // The welcome screen offers the iCloud login again, for this session only (icloud-auto-signin).
        Task { syncedXtream = await logins.xtream() }
    }

    // MARK: Catalog and guide

    private func loadCatalog() async throws {
        guard let client, let credentials else { return }
        let categoryData = try await client.catalog(.liveCategories)
        let channelData = try await client.catalog(.liveStreams)
        let catalog = CatalogCache(categories: categoryData, channels: channelData)
        apply(catalog)
        catalog.save(accountKey: credentials.accountKey)
        AppLog.info(.catalog, "\(channels.count) channels in \(categories.count) categories")
    }

    private func apply(_ catalog: CatalogCache) {
        categories = (try? JSONDecoder().decode([XCategory].self, from: catalog.categories)) ?? []
        channels = (try? JSONDecoder().decode([LiveChannel].self, from: Self.debugEnlargedChannels(catalog.channels))) ?? []
        // Archive channels keep their past programme (catch-up design 5).
        guide.archiveDays = Dictionary(channels.filter { $0.archiveDays > 0 }.map { ($0.id, $0.archiveDays) }, uniquingKeysWith: { a, _ in a })
    }

    /// IPTV_TESTBIGLIVE=<n> (debug): the live channels repeated with new ids up to n, in memory, so
    /// the simulator has a provider-sized channel list (ios-guide-performance). Copies have no
    /// listings of their own.
    private static func debugEnlargedChannels(_ data: Data) -> Data {
        #if DEBUG
        guard let target = ProcessInfo.processInfo.environment["IPTV_TESTBIGLIVE"].flatMap(Int.init),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !items.isEmpty else { return data }
        var out = items
        var copy = 1
        while out.count < target {
            for item in items where out.count < target {
                var item = item
                let base = (item["stream_id"] as? Int) ?? Int("\(item["stream_id"] ?? 0)") ?? 0
                item["stream_id"] = base + copy * 1_000_000
                out.append(item)
            }
            copy += 1
        }
        return (try? JSONSerialization.data(withJSONObject: out)) ?? data
        #else
        return data
        #endif
    }

    func channels(in category: XCategory) -> [LiveChannel] {
        channels.filter { $0.categoryId == category.id }
    }

    /// Loads the channel's programme (call when the channel shows).
    func loadGuide(for channel: LiveChannel) async {
        await guide.load(channel.id, client: client)
    }

    /// What runs now on the channel, once its guide is loaded.
    func currentShow(on channel: LiveChannel, at date: Date = Date()) -> EPGEntry? {
        guide.guide(channel.id).entries?.first { $0.start <= date && date < $0.end }
    }

    // MARK: Playback

    func play(_ channel: LiveChannel) {
        if previewing?.id == channel.id {
            // The preview goes full screen on the same connection.
            previewing = nil
            engine.isMuted = baseMuted
            playing = channel
            noteRecent(channel.id)
            AppLog.info(.player, "play channel \(channel.id) from the preview")
            return
        }
        stopPreview()
        if playingRecording != nil { stopRecordingPlayback() }
        guard let client, let url = client.liveURL(channel.id) else { return }
        if let playing, playing.id != channel.id { tuners.release(playing.id, owner: .player) }
        let tuner = tuners.acquire(channel.id, url: url, owner: .player)
        playing = channel
        noteRecent(channel.id)
        engine.load(tuner: tuner)
        AppLog.info(.player, "play channel \(channel.id): \(channel.displayName)")
    }

    /// "Try Again" on the player's failure card (tvos-player-status design 6): the same item once
    /// more. A live channel gets a fresh connection; a film or recording keeps its saved position
    /// unless playback got further (saving a position near 0 would clear it).
    func retryPlayback() {
        if let recording = playingRecording {
            let key = ResumeStore.recordingKey(recording.id)
            if engine.progress.position > resume.position(key) { resume.save(key, position: engine.progress.position, duration: engine.progress.duration) }
            engine.stop()
            playingRecording = nil
            play(recording)
        } else if let item = playingVOD {
            if let key = item.resumeKey, engine.progress.position > resume.position(key) {
                resume.save(key, position: engine.progress.position, duration: engine.progress.duration)
            }
            jellyfinPlayback?.stop()
            jellyfinPlayback = nil
            engine.stop()
            playingVOD = nil
            play(item)
        } else if let channel = playing {
            AppLog.info(.player, "retry channel \(channel.id)")
            engine.stop()
            tuners.release(channel.id, owner: .player)
            play(channel)
        }
    }

    func stop() {
        if playingRecording != nil { stopRecordingPlayback(); return }
        if playingVOD != nil { stopVOD(); return }
        guard let playing else { return }
        AppLog.info(.player, "stop channel \(playing.id)")
        engine.stop()
        tuners.release(playing.id, owner: .player)
        self.playing = nil
    }

    // MARK: Preview

    /// Plays `channel` muted in Live TV's pane, unless that needs a connection a recording holds.
    func startPreview(_ channel: LiveChannel) {
        guard playing == nil, previewing?.id != channel.id, let client, let url = client.liveURL(channel.id) else { return }
        let blocked = tuners.blockers(for: channel.id, as: .player).contains { $0.owners != [.player] }
        guard !blocked else {
            AppLog.detail(.player, "no preview of \(channel.displayName): the account's streams are in use")
            stopPreview()
            return
        }
        stopPreview()
        baseMuted = engine.isMuted
        previewSound = false
        engine.isMuted = true
        let tuner = tuners.acquire(channel.id, url: url, owner: .player)
        previewing = channel
        engine.load(tuner: tuner)
        AppLog.info(.player, "preview channel \(channel.id): \(channel.displayName)")
    }

    func stopPreview() {
        guard let previewing else { return }
        engine.stop()
        tuners.release(previewing.id, owner: .player)
        self.previewing = nil
        engine.isMuted = baseMuted
    }

    /// Play/Pause on a channel row: the preview's sound on or off (debug builds stay muted).
    func togglePreviewSound() {
        guard previewing != nil else { return }
        previewSound.toggle()
        engine.isMuted = baseMuted || !previewSound
    }

    func togglePause() { engine.togglePause() }
    func skip(by seconds: Double) { engine.seek(by: seconds) }
    func goLive() { engine.goLive() }

    // MARK: Debug

    /// Debug builds never use the keychain with FERNSY_NO_KEYCHAIN=1 (like the Mac app).
    static var skipKeychain: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["FERNSY_NO_KEYCHAIN"] == "1"
        #else
        false
        #endif
    }

    /// IPTV_SERVER/IPTV_USER/IPTV_PASS (debug builds): sign in without the keychain.
    static var debugCredentials: XtreamCredentials? {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        // An empty IPTV_SERVER= starts without an account (the welcome screen).
        guard let server = env["IPTV_SERVER"], !server.isEmpty, let user = env["IPTV_USER"], let pass = env["IPTV_PASS"] else { return nil }
        return XtreamCredentials(server: server, username: user, password: pass)
        #else
        nil
        #endif
    }

    #if DEBUG
    /// IPTV_AUTOPLAY=live:<channel id>: plays that channel once the catalog is loaded.
    private func autoplay() {
        guard let spec = ProcessInfo.processInfo.environment["IPTV_AUTOPLAY"], spec.hasPrefix("live:"),
              let id = Int(spec.dropFirst(5)), let channel = channels.first(where: { $0.id == id }), playing == nil else { return }
        play(channel)
    }
    #endif
}

/// The live catalog as the server sent it, in Caches: tvOS may delete it, then it loads again.
struct CatalogCache: Codable {
    let categories: Data
    let channels: Data

    private static func url(accountKey: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fernsy/\(accountKey)/live-catalog.json")
    }

    static func load(accountKey: String) -> CatalogCache? {
        guard let data = try? Data(contentsOf: url(accountKey: accountKey)) else { return nil }
        return try? JSONDecoder().decode(CatalogCache.self, from: data)
    }

    func save(accountKey: String) {
        let url = Self.url(accountKey: accountKey)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
