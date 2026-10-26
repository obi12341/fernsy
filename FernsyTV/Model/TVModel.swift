import Combine
import FernsyCore
import FernsyPlayer
import Foundation

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
    /// Launched with stored credentials: the sign-in at launch shows progress, not the welcome screen.
    private(set) var startedWithAccount = false

    let engine = PlayerEngine()
    let guide = EPGStore()
    private let tuners = TunerPool()
    private(set) var client: XtreamClient?

    static let shared = TVModel()

    /// Timeshift buffer on Apple TV: Caches, which tvOS may need back (design F).
    static let timeshiftSeconds: Double = 30 * 60

    private init() {
        tuners.keepSeconds = Self.timeshiftSeconds
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
        if !remember, let cached = CatalogCache.load(accountKey: credentials.accountKey) { apply(cached) }
        do {
            let account = try await client.account()
            self.client = client
            self.credentials = credentials
            maxConnections = max(1, account.maxConnections ?? 1)
            tuners.limit = maxConnections
            if remember && !Self.skipKeychain { CredentialStore.save(credentials) }
            signIn = .signedIn
            AppLog.info(.app, "signed in, \(maxConnections) stream(s)")
            try await loadCatalog()
            #if DEBUG
            autoplay()
            #endif
        } catch {
            signIn = channels.isEmpty ? .failed(error.localizedDescription) : .signedIn
            AppLog.error(.catalog, "sign-in or catalog failed: \(error.localizedDescription)")
        }
    }

    func signOut() {
        stop()
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
        guard let client, let url = client.liveURL(channel.id) else { return }
        if let playing, playing.id != channel.id { tuners.release(playing.id, owner: .player) }
        let tuner = tuners.acquire(channel.id, url: url, owner: .player)
        playing = channel
        engine.load(tuner: tuner)
        AppLog.info(.player, "play channel \(channel.id): \(channel.displayName)")
    }

    func stop() {
        guard let playing else { return }
        engine.stop()
        tuners.release(playing.id, owner: .player)
        self.playing = nil
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
