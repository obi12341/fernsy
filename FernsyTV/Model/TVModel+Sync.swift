import FernsyCore
import FernsyPlayer
import Foundation

/// The Apple TV's side of icloud-sync: SyncStore mirrors the synced UserDefaults keys and
/// resume positions; this applies what arrives, keeps the account's hidden channels and pinned
/// categories in step and offers logins found in iCloud. Keychain-less runs (UI tests) sync
/// only with IPTV_SYNC=1.
extension TVModel {
    static var syncAllowed: Bool { ICloudSync.allowed(skipKeychain: skipKeychain) }
    static let syncedKeys = ICloudSync.syncedKeys

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
        Task {
            if signingInFromICloud { await signInFromICloud() }
            await refreshSyncedLogins()
        }
    }

    static func makeLogins() -> LoginSync { ICloudSync.makeLogins(allowed: syncAllowed) }

    /// Launched without an account (icloud-auto-signin): signs in with what iCloud has, provider
    /// and Jellyfin each on their own, showing the steps (at least `minimumShown` once something
    /// signed in, until the channels are loaded). What fails stays offered on the welcome screen,
    /// with the reason if nothing could be signed in.
    func signInFromICloud() async {
        iCloudSignInError = await ICloudSync.signInAtLaunch(
            logins: logins, steps: { iCloudSteps }, setSteps: { iCloudSteps = $0 },
            signInIPTV: { login in
                await signIn(login)
                guard case .failed(let message) = signIn else { return nil }
                syncedXtream = login
                return message
            },
            signInJellyfin: { login in
                do {
                    try await jellyfin.signIn(server: login.server, username: login.username, password: login.password)
                    return nil
                } catch {
                    syncedJellyfin = login
                    return error.localizedDescription
                }
            },
            isSignedIn: { credentials != nil || jellyfin.session != nil })
        signingInFromICloud = false
    }

    private func syncArrived(_ names: Set<String>) {
        let arrived = ICloudSync.arrived(names)
        if let value = arrived.favorites { favorites = value }
        if let value = arrived.recentChannels { recentChannels = value }
        if arrived.resume { resumeRevision += 1 }
        // Films or series switched on another device: as if switched here (drops or downloads).
        if let value = arrived.showsMovies { showsIPTVMovies = value }
        if let value = arrived.showsSeries { showsIPTVSeries = value }
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
        if let remote = ICloudSync.pullNewer(ChannelVisibility.self, name: hiddenName, local: visibility, modifiedAt: visibility.modifiedAt, sync: sync) {
            visibility = remote
            store(remote.encoded, as: "live.visibility")
        }
        let pinnedName = SyncStore.accountName(account, "pinned")
        if let remote = ICloudSync.pullNewer(PinnedCategories.self, name: pinnedName, local: pinned, modifiedAt: pinned.modifiedAt, sync: sync) {
            pinned = remote
            store(remote.encoded, as: "live.pinned")
        }
    }

    /// Signed in: the login goes to iCloud if it is not there yet. Without an account: what iCloud
    /// has is offered on the welcome screen.
    func refreshSyncedLogins() async {
        await ICloudSync.refreshLogins(logins, available: { iCloudAvailable = $0 },
                                       credentials: credentials, offerXtream: !startedWithAccount, offeredXtream: { syncedXtream = $0 },
                                       jellyfinLogin: jellyfin.login, jellyfinSignedIn: jellyfin.session != nil,
                                       offeredJellyfin: { syncedJellyfin = $0 })
    }
}
