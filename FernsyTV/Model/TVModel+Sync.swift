import FernsyCore
import FernsyPlayer
import Foundation

/// The Apple TV's side of icloud-sync: SyncStore mirrors the synced UserDefaults keys and
/// resume positions; this applies what arrives, keeps the account's hidden channels and pinned
/// categories in step and offers logins found in iCloud. Keychain-less runs (UI tests) sync
/// only with IPTV_SYNC=1.
extension TVModel {
    static var syncAllowed: Bool { !skipKeychain || ProcessInfo.processInfo.environment["IPTV_SYNC"] == "1" }
    static let syncedKeys = [LiveRules.favoritesKey, LiveRules.recentKey, TrackPreferences.audioKey,
                             TrackPreferences.subtitlesKey, Recorder.padBeforeKey, Recorder.padAfterKey]

    func startSync() {
        sync.onChange = { [weak self] names in self?.syncArrived(names) }
        sync.start()
        #if DEBUG
        // IPTV_TESTDEFAULTS=<key>=<int|text>,…: a settings change as if made here (sync tests
        // on a real Apple TV, without the remote).
        for pair in (ProcessInfo.processInfo.environment["IPTV_TESTDEFAULTS"] ?? "").split(separator: ",") {
            let p = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard p.count == 2 else { continue }
            if let number = Int(p[1]) { UserDefaults.standard.set(number, forKey: p[0]) } else { UserDefaults.standard.set(p[1], forKey: p[0]) }
        }
        #endif
        jellyfin.onSignedIn = { [weak self] login in
            guard let self else { return }
            syncedJellyfin = nil
            Task { await self.logins.save(login) }
        }
        Task { await refreshSyncedLogins() }
    }

    private func syncArrived(_ names: Set<String>) {
        let defaults = UserDefaults.standard
        if names.contains("d." + LiveRules.favoritesKey) { favorites = Set(defaults.stringArray(forKey: LiveRules.favoritesKey) ?? []) }
        if names.contains("d." + LiveRules.recentKey) { recentChannels = defaults.array(forKey: LiveRules.recentKey) as? [Int] ?? [] }
        if names.contains("resume") { objectWillChange.send() }
        pullLiveValues()
    }

    func pushLiveValue<T: Encodable>(_ value: T, _ name: String, _ modifiedAt: Date) {
        guard let account = credentials?.accountKey else { return }
        sync.push(value, as: SyncStore.accountName(account, name), modifiedAt: modifiedAt)
    }

    /// The account's hidden channels and pinned categories: the newer of this Apple TV's and
    /// iCloud's; sent once if iCloud has none yet.
    func pullLiveValues() {
        guard let account = credentials?.accountKey else { return }
        let hiddenName = SyncStore.accountName(account, "visibility")
        if let remote = sync.pull(ChannelVisibility.self, name: hiddenName, newerThan: visibility.modifiedAt) {
            visibility = remote
            store(remote.encoded, as: "live.visibility")
        } else if !sync.hasValue(hiddenName) && visibility.modifiedAt.timeIntervalSince1970 > 0 {
            sync.push(visibility, as: hiddenName, modifiedAt: visibility.modifiedAt)
        }
        let pinnedName = SyncStore.accountName(account, "pinned")
        if let remote = sync.pull(PinnedCategories.self, name: pinnedName, newerThan: pinned.modifiedAt) {
            pinned = remote
            store(remote.encoded, as: "live.pinned")
        } else if !sync.hasValue(pinnedName) && pinned.modifiedAt.timeIntervalSince1970 > 0 {
            sync.push(pinned, as: pinnedName, modifiedAt: pinned.modifiedAt)
        }
    }

    /// Signed in: the login goes to iCloud if it is not there yet. Without an account: what iCloud
    /// has is offered on the welcome screen.
    func refreshSyncedLogins() async {
        iCloudAvailable = await logins.isAvailable()
        guard iCloudAvailable else { AppLog.info(.app, "iCloud: not available"); return }
        if let credentials {
            if await logins.xtream() == nil { await logins.save(credentials) }
        } else if !startedWithAccount {
            syncedXtream = await logins.xtream()
            if let login = syncedXtream { AppLog.info(.app, "iCloud: offers the IPTV login at \(login.baseURL?.host() ?? login.server)") }
        }
        if let login = jellyfin.login {
            if await logins.jellyfin() == nil { await logins.save(login) }
        } else if jellyfin.session == nil {
            syncedJellyfin = await logins.jellyfin()
            if let login = syncedJellyfin { AppLog.info(.app, "iCloud: offers the Jellyfin login at \(URL(string: login.server)?.host() ?? login.server)") }
        }
        #if DEBUG
        // IPTV_TESTUSESYNCED=1: takes the offered logins as a click on "Use" would (real Apple TV).
        if ProcessInfo.processInfo.environment["IPTV_TESTUSESYNCED"] == "1" {
            if let login = syncedXtream { await signIn(login) }
            if let login = syncedJellyfin { try? await jellyfin.signIn(server: login.server, username: login.username, password: login.password) }
        }
        #endif
    }
}
