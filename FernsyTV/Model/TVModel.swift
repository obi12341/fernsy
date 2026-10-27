import Combine
import FernsyCore
import FernsyPlayer
import Foundation
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
    }

    @Published private(set) var signIn: SignIn = .signedOut
    @Published private(set) var credentials: XtreamCredentials?
    @Published private(set) var maxConnections = 1
    @Published private(set) var categories: [XCategory] = []
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
    @Published var movies: [Movie] = []
    @Published var seriesCategories: [XCategory] = []
    @Published var series: [Series] = []
    @Published var movieInfo: [Int: MovieDetails] = [:]
    @Published var seriesInfo: [Int: SeriesInfo] = [:]
    /// The film, episode or Jellyfin item in the player, nil when none plays.
    @Published var playingVOD: VODItem?
    var jellyfinPlayback: JellyfinPlayback?
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

    let engine = PlayerEngine()
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
        }
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
            #if DEBUG
            // IPTV_MAXCONN=<n>: the account's stream limit for this run (single-stream tests).
            if let value = ProcessInfo.processInfo.environment["IPTV_MAXCONN"].flatMap(Int.init) { maxConnections = max(1, value) }
            #endif
            tuners.limit = maxConnections
            if remember && !Self.skipKeychain { CredentialStore.save(credentials) }
            loadLiveState()
            #if DEBUG
            // IPTV_FRESHRECORDINGS=1: start without the recordings of earlier test runs.
            if ProcessInfo.processInfo.environment["IPTV_FRESHRECORDINGS"] == "1" {
                try? FileManager.default.removeItem(at: Self.recordingsDirectory(accountKey: credentials.accountKey))
            }
            #endif
            recorder.activate(accountKey: credentials.accountKey)
            signIn = .signedIn
            AppLog.info(.app, "signed in, \(maxConnections) stream(s)")
            try await loadCatalog()
            Task { await loadLibraryCatalog() }
            #if DEBUG
            autoplay()
            testRecord()
            #endif
        } catch {
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
        channels = (try? JSONDecoder().decode([LiveChannel].self, from: catalog.channels)) ?? []
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
