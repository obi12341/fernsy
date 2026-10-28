import Foundation

/// The Jellyfin account and its film and series library.
///
/// Independent of the IPTV account: both can be signed in at the same time. The session
/// (server, user, token) and the password are kept in the keychain, so a rejected token is
/// renewed without asking; the library is cached on disk and shown before the background
/// refresh, like the IPTV catalog.
@MainActor
public final class JellyfinStore: ObservableObject {
    @Published public private(set) var session: JFSession?
    /// The server rejected the token (session ended in the dashboard, password changed).
    @Published public private(set) var isExpired = false
    /// The last refresh could not reach the server; the cached library is shown.
    @Published public private(set) var isOffline = false
    @Published public private(set) var isLoading = false
    @Published public var lastError: String?

    /// Film and series libraries, in the server's order.
    @Published public private(set) var libraries: [JFItem] = []
    @Published public private(set) var films: [JFItem] = []
    @Published public private(set) var series: [JFItem] = []
    /// Item id → ids of the libraries it is in.
    public private(set) var membership: [String: Set<String>] = [:]

    @Published public private(set) var resume: [JFItem] = []
    @Published public private(set) var nextUp: [JFItem] = []
    @Published public private(set) var latestFilms: [JFItem] = []
    @Published public private(set) var latestSeries: [JFItem] = []

    /// Detail data loaded on demand, updated together with the lists when marks change.
    @Published public private(set) var details: [String: JFItem] = [:]
    @Published public private(set) var seasons: [String: [JFItem]] = [:]
    @Published public private(set) var episodes: [String: [JFItem]] = [:]

    private let skipKeychain: Bool
    private var refreshTask: Task<Void, Never>?

    /// Kept for renewing the session; nil for sessions signed in before it was stored.
    private var password: String?
    private var renewal: Task<Bool, Never>?
    /// After a successful sign-in, with the login the apps save to iCloud (icloud-sync).
    public var onSignedIn: ((LoginSync.JellyfinLogin) -> Void)?

    /// The signed-in login as synced to the user's other devices: never the session.
    public var login: LoginSync.JellyfinLogin? {
        guard let session, let password else { return nil }
        return LoginSync.JellyfinLogin(server: session.server, username: session.userName, password: password)
    }

    /// Keychain accounts; debug runs can use their own (JF_KEYCHAIN_SUFFIX=test).
    private static var keychainAccount: String {
        #if DEBUG
        if let suffix = ProcessInfo.processInfo.environment["JF_KEYCHAIN_SUFFIX"] { return "jellyfin.\(suffix)" }
        #endif
        return "jellyfin"
    }
    private static var passwordAccount: String { keychainAccount + ".password" }

    public init(skipKeychain: Bool) {
        self.skipKeychain = skipKeychain
        if !skipKeychain, let saved = Keychain.load(JFSession.self, account: Self.keychainAccount) {
            session = saved
            password = Keychain.load(String.self, account: Self.passwordAccount)
            Task { await loadLibrary(forceRefresh: false) }
        }
        #if DEBUG
        debugSignIn()
        #endif
    }

    public var client: JellyfinClient? {
        guard let session, let base = session.baseURL else { return nil }
        return JellyfinClient(base: base, token: session.token)
    }

    // MARK: Session

    public func signIn(server: String, username: String, password: String) async throws {
        guard let base = JFSession.normalize(server) else { throw JellyfinError.invalidURL }
        let anonymous = JellyfinClient(base: base, token: nil)
        let info: JFPublicInfo
        let auth: JFAuthResult
        do {
            info = try await anonymous.publicInfo()
            auth = try await anonymous.authenticate(username: username, password: password)
        } catch {
            AppLog.error(.jellyfin, "sign-in at \(base.host() ?? server) failed: \(error.localizedDescription)")
            throw error
        }
        AppLog.info(.jellyfin, "signed in at \(base.host() ?? server)")
        let newSession = JFSession(server: base.absoluteString, serverId: info.id ?? "", serverName: info.serverName ?? base.host() ?? "",
                                   version: info.version ?? "", userId: auth.user.id, userName: auth.user.name, token: auth.accessToken)
        if !skipKeychain {
            Keychain.save(newSession, account: Self.keychainAccount)
            Keychain.save(password, account: Self.passwordAccount)
        }
        self.password = password
        reset()
        session = newSession
        isExpired = false
        onSignedIn?(LoginSync.JellyfinLogin(server: newSession.server, username: username, password: password))
        await loadLibrary(forceRefresh: true)
    }

    public func signOut() {
        AppLog.info(.jellyfin, "signed out")
        if let client { Task { await client.logout() } }
        if !skipKeychain {
            Keychain.delete(account: Self.keychainAccount)
            Keychain.delete(account: Self.passwordAccount)
        }
        password = nil
        session = nil
        isExpired = false
        reset()
    }

    private func reset() {
        refreshTask?.cancel()
        libraries = []; films = []; series = []; membership = [:]
        resume = []; nextUp = []; latestFilms = []; latestSeries = []
        details = [:]; seasons = [:]; episodes = [:]
        isOffline = false
        lastError = nil
    }

    /// Every request goes through here: a rejected token is renewed with the stored password and
    /// the request repeated once; only when that fails is the session marked expired. An
    /// unreachable server marks it offline.
    public func call<T>(_ body: (JellyfinClient, String) async throws -> T) async throws -> T {
        guard let client, let userId = session?.userId else { throw JellyfinError.unauthorized }
        do {
            let result = try await body(client, userId)
            isOffline = false
            return result
        } catch JellyfinError.unauthorized {
            if await renewSession(), let renewed = self.client {
                do {
                    let result = try await body(renewed, userId)
                    isOffline = false
                    return result
                } catch JellyfinError.unauthorized {}
            }
            isExpired = true
            throw JellyfinError.unauthorized
        } catch let error as URLError where error.code != .cancelled {
            isOffline = true
            throw error
        }
    }

    /// Signs in again with the stored password after the server rejected the token. Callers
    /// that arrive while a renewal runs wait for the same one. True when there is a new token.
    public func renewSession() async -> Bool {
        if let renewal { return await renewal.value }
        guard let session, let password, let base = session.baseURL else { return false }
        let task = Task { @MainActor () -> Bool in
            do {
                let auth = try await JellyfinClient(base: base, token: nil).authenticate(username: session.userName, password: password)
                guard auth.user.id == session.userId else { return false }
                self.session?.token = auth.accessToken
                if !skipKeychain, let renewed = self.session { Keychain.save(renewed, account: Self.keychainAccount) }
                isExpired = false
                AppLog.info(.jellyfin, "session renewed")
                return true
            } catch {
                AppLog.error(.jellyfin, "session renewal failed: \(error.localizedDescription)")
                return false
            }
        }
        renewal = task
        let renewed = await task.value
        renewal = nil
        return renewed
    }

    // MARK: Library

    /// Shows the cached library first, then refreshes it from the server.
    public func loadLibrary(forceRefresh: Bool) async {
        guard session != nil else { return }
        if films.isEmpty && series.isEmpty { loadCache() }
        // One refresh at a time; a forced one replaces a running one.
        if let running = refreshTask, !forceRefresh {
            await running.value
            return
        }
        refreshTask?.cancel()
        let task = Task { await refresh() }
        refreshTask = task
        await task.value
        if refreshTask == task { refreshTask = nil }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let views = try await call { try await $0.views(userId: $1) }
            let libs = views.filter { $0.collectionType == "movies" || $0.collectionType == "tvshows" }
            var newFilms: [String: JFItem] = [:], newSeries: [String: JFItem] = [:], newMembership: [String: Set<String>] = [:]
            for lib in libs {
                let type = lib.collectionType == "movies" ? "Movie" : "Series"
                var start = 0
                while true {
                    let page = try await call { try await $0.items(userId: $1, parentId: lib.id, type: type, start: start, limit: 500) }
                    for item in page.items {
                        if type == "Movie" { newFilms[item.id] = item } else { newSeries[item.id] = item }
                        newMembership[item.id, default: []].insert(lib.id)
                    }
                    start += page.items.count
                    if page.items.isEmpty || start >= (page.totalRecordCount ?? start) { break }
                }
                try Task.checkCancellation()
            }
            libraries = libs
            films = newFilms.values.sorted(by: Self.byName)
            series = newSeries.values.sorted(by: Self.byName)
            membership = newMembership
            saveCache()
            #if DEBUG
            films = Self.debugMany(films)
            series = Self.debugMany(series)
            #endif
            AppLog.info(.jellyfin, "\(libs.count) libraries, \(films.count) films, \(series.count) series")
            await refreshHome()
        } catch {
            // Offline and expired have their own notices.
            if !(error is CancellationError || error is URLError || (error as? JellyfinError) == .unauthorized) {
                lastError = error.localizedDescription
            }
            AppLog.warning(.jellyfin, "refresh failed: \(error)")
        }
    }

    private static func byName(_ a: JFItem, _ b: JFItem) -> Bool {
        (a.sortName ?? a.name).localizedStandardCompare(b.sortName ?? b.name) == .orderedAscending
    }

    /// Watched state and favorites of everything, e.g. after watching on another client.
    public func refreshUserData() async {
        guard !libraries.isEmpty else { return }
        do {
            var updates: [String: JFUserData] = [:]
            for lib in libraries {
                let type = lib.collectionType == "movies" ? "Movie" : "Series"
                for item in try await call({ try await $0.userData(userId: $1, parentId: lib.id, type: type) }) {
                    if let data = item.userData { updates[item.id] = data }
                }
            }
            apply(updates)
            await refreshHome()
        } catch {}
    }

    public func refreshHome() async {
        guard session != nil else { return }
        resume = (try? await call { try await $0.resume(userId: $1) }) ?? resume
        nextUp = (try? await call { try await $0.nextUp(userId: $1) }) ?? nextUp
        var films: [JFItem] = [], shows: [JFItem] = []
        for lib in libraries {
            let latest = (try? await call { try await $0.latest(userId: $1, parentId: lib.id) }) ?? []
            if lib.collectionType == "movies" { films += latest } else { shows += latest }
        }
        latestFilms = Array(films.sorted { $0.addedKey > $1.addedKey }.prefix(24))
        latestSeries = Array(shows.sorted { $0.addedKey > $1.addedKey }.prefix(24))
        #if DEBUG
        latestFilms = Array(Self.debugMany(latestFilms).prefix(24))
        #endif
        fillHomeFromLibrary()
    }

    /// Without the server (offline, before the first answer) Home still shows what the cached
    /// library knows: newest films and series, and films with a resume position.
    private func fillHomeFromLibrary() {
        if latestFilms.isEmpty { latestFilms = Array(films.sorted { $0.addedKey > $1.addedKey }.prefix(24)) }
        if latestSeries.isEmpty { latestSeries = Array(series.sorted { $0.addedKey > $1.addedKey }.prefix(24)) }
        if resume.isEmpty { resume = films.filter { $0.progress != nil } }
    }

    public func libraries(of item: JFItem) -> Set<String> { membership[item.id] ?? [] }

    // MARK: Details

    public func loadDetail(_ id: String) async {
        if let item = try? await call({ try await $0.item(userId: $1, id: id) }) { details[id] = item }
    }

    public func loadSeasons(_ seriesId: String) async {
        if let list = try? await call({ try await $0.seasons(userId: $1, seriesId: seriesId) }) { seasons[seriesId] = list }
    }

    public func loadEpisodes(seriesId: String, seasonId: String) async {
        if let list = try? await call({ try await $0.episodes(userId: $1, seriesId: seriesId, seasonId: seasonId) }) { episodes[seasonId] = list }
    }

    /// After playback: the item's (and its series') new watched state and position.
    public func refreshAfterPlayback(_ id: String) async {
        guard let item = try? await call({ try await $0.item(userId: $1, id: id) }) else { return }
        details[id] = item
        if let data = item.userData { apply([id: data]) }
        await reloadAround(item)
    }

    /// The episode to start for "Play" on a series: Next Up, else the first episode.
    public func episodeToPlay(seriesId: String) async -> JFItem? {
        if let next = nextUp.first(where: { $0.seriesId == seriesId }) { return next }
        await loadSeasons(seriesId)
        guard let first = seasons[seriesId]?.first else { return nil }
        await loadEpisodes(seriesId: seriesId, seasonId: first.id)
        return episodes[first.id]?.first
    }

    // MARK: Watched and favorites

    /// Only these may be marked: marking a library folder (or the user's root folder, which an
    /// unknown id can resolve to) as played marks everything below it.
    public static let markableTypes: Set<String> = ["Movie", "Episode", "Season", "Series"]

    public func setPlayed(_ item: JFItem, _ played: Bool) async {
        guard Self.markableTypes.contains(item.type) else { return }
        var optimistic = item.userData ?? JFUserData()
        optimistic.played = played
        optimistic.playbackPositionTicks = 0
        if item.isFolder { optimistic.unplayedItemCount = played ? 0 : nil }
        let previous = item.userData
        apply([item.id: optimistic])
        do {
            let data = try await call { try await $0.setPlayed(userId: $1, itemId: item.id, played: played) }
            apply([item.id: data])
            // Children and parents changed on the server too: reload what is on screen.
            await reloadAround(item)
        } catch {
            if let previous { apply([item.id: previous]) }
            lastError = String(localized: "Could not mark “\(item.name)”: \(error.localizedDescription)", bundle: .module)
        }
    }

    public func setFavorite(_ item: JFItem, _ favorite: Bool) async {
        guard Self.markableTypes.contains(item.type) else { return }
        var optimistic = item.userData ?? JFUserData()
        optimistic.isFavorite = favorite
        let previous = item.userData
        apply([item.id: optimistic])
        do {
            let data = try await call { try await $0.setFavorite(userId: $1, itemId: item.id, favorite: favorite) }
            apply([item.id: data])
        } catch {
            if let previous { apply([item.id: previous]) }
            lastError = String(localized: "Could not change “\(item.name)”: \(error.localizedDescription)", bundle: .module)
        }
    }

    private func reloadAround(_ item: JFItem) async {
        let seriesId = item.isSeries ? item.id : item.seriesId
        if let seriesId {
            if let show = try? await call({ try await $0.item(userId: $1, id: seriesId) }), let data = show.userData {
                apply([seriesId: data])
            }
            if seasons[seriesId] != nil { await loadSeasons(seriesId) }
            for season in seasons[seriesId] ?? [] where episodes[season.id] != nil {
                await loadEpisodes(seriesId: seriesId, seasonId: season.id)
            }
        }
        await refreshHome()
    }

    /// Puts new user data into every list holding the item.
    private func apply(_ updates: [String: JFUserData]) {
        guard !updates.isEmpty else { return }
        func patch(_ list: inout [JFItem]) {
            for i in list.indices { if let data = updates[list[i].id] { list[i].userData = data } }
        }
        patch(&films); patch(&series); patch(&resume); patch(&nextUp); patch(&latestFilms); patch(&latestSeries)
        for (id, data) in updates where details[id] != nil { details[id]?.userData = data }
        for key in seasons.keys { patch(&seasons[key]!) }
        for key in episodes.keys { patch(&episodes[key]!) }
        saveCache()
    }

    // MARK: Artwork

    public func posterURL(_ item: JFItem, height: Int = 450) -> String? {
        if let tag = item.imageTags?["Primary"] { return client?.imageURL(itemId: item.id, type: "Primary", tag: tag, maxHeight: height) }
        if let seriesId = item.seriesId, let tag = item.seriesPrimaryImageTag {
            return client?.imageURL(itemId: seriesId, type: "Primary", tag: tag, maxHeight: height)
        }
        return nil
    }

    public func backdropURL(_ item: JFItem, height: Int = 900) -> String? {
        if let tag = item.backdropImageTags?.first { return client?.imageURL(itemId: item.id, type: "Backdrop", tag: tag, maxHeight: height) }
        if let parent = item.parentBackdropItemId, let tag = item.parentBackdropImageTags?.first {
            return client?.imageURL(itemId: parent, type: "Backdrop", tag: tag, maxHeight: height)
        }
        return nil
    }

    /// Landscape still for episodes and home rows; falls back to the series' artwork.
    public func thumbURL(_ item: JFItem, height: Int = 360) -> String? {
        if let tag = item.imageTags?["Primary"], item.type == "Episode" {
            return client?.imageURL(itemId: item.id, type: "Primary", tag: tag, maxHeight: height)
        }
        if let tag = item.imageTags?["Thumb"] { return client?.imageURL(itemId: item.id, type: "Thumb", tag: tag, maxHeight: height) }
        if let parent = item.parentThumbItemId, let tag = item.parentThumbImageTag {
            return client?.imageURL(itemId: parent, type: "Thumb", tag: tag, maxHeight: height)
        }
        return backdropURL(item, height: height)
    }

    // MARK: Cache

    private struct Cache: Codable {
        var libraries: [JFItem]
        var films: [JFItem]
        var series: [JFItem]
        var membership: [String: Set<String>]
    }

    /// Where the library cache lives: Application Support on the Mac; the Apple TV sets Caches.
    nonisolated(unsafe) public static var cacheBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    private var cacheURL: URL? {
        guard let session else { return nil }
        let dir = Self.cacheBase.appendingPathComponent("Fernsy/\(session.cacheKey)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    #if DEBUG
    /// JF_TESTMANY=<n>: the films and series (and Recently Added) repeated with new ids up to n
    /// each, in memory and not cached, so a small test server fills grids and rows (layout tests, tvos-edge-scrolling).
    /// Copies have no artwork on the server and show the placeholder.
    private static func debugMany(_ items: [JFItem]) -> [JFItem] {
        guard let target = ProcessInfo.processInfo.environment["JF_TESTMANY"].flatMap(Int.init), !items.isEmpty,
              let originals = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(items)) as? [[String: Any]] else { return items }
        var copies: [[String: Any]] = []
        var round = 1
        while items.count + copies.count < target {
            for var item in originals where items.count + copies.count < target {
                item["id"] = "\(item["id"] ?? "")-\(round)"
                item["name"] = "\(item["name"] ?? "") \(round)"
                // Varied, so the overview's rows (tvos-jellyfin-overview) have something to show.
                let genres = ["Comedy", "Drama", "Action", "Thriller", "Documentary"]
                item["communityRating"] = 5.5 + Double(round % 5)
                item["productionYear"] = 1985 + (round * 7) % 40
                item["genres"] = [genres[round % genres.count], genres[(round + 2) % genres.count]]
                let isSeries = (item["type"] as? String) == "Series"
                item["runTimeTicks"] = Int64(isSeries ? 45 : 80 + (round * 7) % 70) * 600_000_000
                var user = item["userData"] as? [String: Any] ?? [:]
                user["played"] = !isSeries && round % 4 == 0
                user["isFavorite"] = round % 6 == 0
                if !isSeries && round % 4 == 0 { user["lastPlayedDate"] = "2023-0\(1 + round % 9)-01T20:00:00.0000000Z" }
                if isSeries {
                    item["recursiveItemCount"] = 10
                    user["unplayedItemCount"] = [10, 2, 1, 3, 6][round % 5]
                }
                item["userData"] = user
                copies.append(item)
            }
            round += 1
        }
        guard let data = try? JSONSerialization.data(withJSONObject: copies),
              let decoded = try? JSONDecoder().decode([JFItem].self, from: data) else { return items }
        return items + decoded
    }
    #endif

    private func loadCache() {
        guard let url = cacheURL, let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        libraries = cache.libraries
        films = cache.films
        series = cache.series
        #if DEBUG
        films = Self.debugMany(films)
        series = Self.debugMany(series)
        #endif
        membership = cache.membership
        fillHomeFromLibrary()
        AppLog.detail(.jellyfin, "cache: \(films.count) films, \(series.count) series")
    }

    private func saveCache() {
        guard let url = cacheURL, !libraries.isEmpty else { return }
        let cache = Cache(libraries: libraries, films: films, series: series, membership: membership)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Debug

    #if DEBUG
    /// JF_SERVER/JF_USER/JF_PASS: sign in without the keychain (like IPTV_SERVER for Xtream).
    /// JF_TOKEN=<anything> with them replaces the token afterwards (tests the expired state).
    private func debugSignIn() {
        let env = ProcessInfo.processInfo.environment
        if let spec = env["JF_CACHEONLY"]?.split(separator: "|").map(String.init), spec.count == 3 {
            // JF_CACHEONLY=<server>|<serverId>|<userId>: show the cached library without signing in
            // (artwork is public); every request fails, so nothing is written. For UI profiling.
            session = JFSession(server: spec[0], serverId: spec[1], serverName: "Cache", version: "", userId: spec[2], userName: "", token: "none")
            loadCache()
            return
        }
        guard let server = env["JF_SERVER"], let user = env["JF_USER"], let pass = env["JF_PASS"] else { return }
        Task {
            do {
                try await signIn(server: server, username: user, password: pass)
                if env["JF_SELFTEST"] != nil { await debugSelfTest() }
                if let spec = env["JF_TESTMARK"] { await debugMark(spec) }
                if env["JF_OFFLINE"] != nil {
                    // JF_OFFLINE=1: point the session at an unreachable address (nothing reaches
                    // the server), then refresh and try to mark an unwatched film.
                    session?.server = "https://127.0.0.1:9"
                    await loadLibrary(forceRefresh: true)
                    debugLog("[test] offline=\(isOffline), films still shown: \(films.count)")
                    if let film = films.first(where: { !$0.isPlayed }) {
                        await setPlayed(film, true)
                        let shown = films.first { $0.id == film.id }
                        debugLog("[test] offline mark reverted: \(shown?.isPlayed == false), error: \(lastError ?? "none")")
                    }
                }
                if let fake = env["JF_TOKEN"] {
                    // With JF_BADPASS=1 the renewal fails too (password changed on the server).
                    if env["JF_BADPASS"] == "1" { password = "wrong" }
                    session?.token = fake
                    await refreshUserData()
                    debugLog("[test] fake token, expired=\(isExpired)")
                }
            } catch {
                debugLog("[test] debug sign-in failed: \(error.localizedDescription)")
            }
        }
    }

    /// JF_TESTMARK=played:<id>:1,fav:<id>:0,…: marks items like the buttons do and logs the
    /// state the lists show afterwards (optimistic update plus server answer).
    private func debugMark(_ spec: String) async {
        for step in spec.split(separator: ",") {
            let parts = step.split(separator: ":").map(String.init)
            guard parts.count == 3 else { continue }
            await loadDetail(parts[1])
            guard let item = details[parts[1]] else { continue }
            let on = parts[2] == "1"
            if parts[0] == "played" { await setPlayed(item, on) } else { await setFavorite(item, on) }
            let shown = (films + series).first { $0.id == item.id } ?? details[item.id]
            debugLog("[test] mark \(step) (\(item.type)): played=\(shown?.isPlayed ?? false) favorite=\(shown?.isFavorite ?? false) unplayed=\(shown?.userData?.unplayedItemCount ?? -1) error=\(lastError ?? "none")")
            lastError = nil
        }
    }

    /// JF_SELFTEST=1: every read route once, results to the log.
    private func debugSelfTest() async {
        guard let film = films.first, let show = series.first else { return }
        await loadDetail(film.id)
        let detail = details[film.id]
        debugLog("[test] detail \(detail?.name ?? "–"): people \(detail?.people?.count ?? -1), sources \(detail?.mediaSources?.count ?? -1), streams \(detail?.mediaSources?.first?.mediaStreams?.count ?? -1)")
        await loadSeasons(show.id)
        let seasonList = seasons[show.id] ?? []
        debugLog("[test] seasons of a series: \(seasonList.count)")
        if let first = seasonList.first {
            await loadEpisodes(seriesId: show.id, seasonId: first.id)
            debugLog("[test] episodes of season 1: \(episodes[first.id]?.count ?? -1)")
        }
        debugLog("[test] home: resume \(resume.count), next up \(nextUp.count), latest films \(latestFilms.count), latest series \(latestSeries.count)")
        debugLog("[test] poster url ok: \(posterURL(film) != nil), backdrop url ok: \(backdropURL(film) != nil)")
    }
    #endif
}
