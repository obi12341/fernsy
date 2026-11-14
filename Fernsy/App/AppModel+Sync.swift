import Combine
import FernsyCore
import FernsyPlayer
import Foundation
import SwiftUI

// MARK: iCloud sync

/// The Mac's side of icloud-sync: SyncStore mirrors the synced UserDefaults keys and resume
/// positions; this applies what arrives, keeps the account's hidden channels in step and offers
/// logins found in iCloud.
extension AppModel {
    static var syncAllowed: Bool { ICloudSync.allowed(skipKeychain: skipKeychain) }
    static let syncedKeys = ICloudSync.syncedKeys

    func startSync() {
        sync.onChange = { [weak self] names in self?.syncArrived(names) }
        sync.start()
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
    /// signed in, until the channels are loaded). What fails stays offered on the login screen,
    /// with the reason if nothing could be signed in.
    private func signInFromICloud() async {
        iCloudSignInError = await ICloudSync.signInAtLaunch(
            logins: logins, steps: { iCloudSteps }, setSteps: { iCloudSteps = $0 },
            signInIPTV: { xtream in
                do {
                    try await login(xtream)
                    return nil
                } catch {
                    syncedXtream = xtream
                    return error.localizedDescription
                }
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

    /// Values from another device: favourites, recently watched and the films and series switches
    /// again from UserDefaults (track languages and padding are read where they are used), hidden
    /// channels from the store.
    private func syncArrived(_ names: Set<String>) {
        let arrived = ICloudSync.arrived(names)
        if let value = arrived.favorites { favorites = value }
        if let value = arrived.recentChannels { recentChannels = value }
        if arrived.resume || names.contains("resumeSeries") {
            resumeRevision += 1
            // Episodes started elsewhere: their series' lists (continue-watching-fresh design 4).
            Task { await loadStartedSeries() }
        }
        // Films or series switched on another device: as if switched here (drops or downloads).
        if let value = arrived.showsMovies { showsIPTVMovies = value }
        if let value = arrived.showsSeries { showsIPTVSeries = value }
        pullVisibility()
    }

    /// The account's hidden categories and channels: the newer of this Mac's and iCloud's; sent
    /// once if iCloud has none yet.
    func pullVisibility() {
        guard let key = credentials?.accountKey else { return }
        let name = SyncStore.accountName(key, "visibility")
        if let remote = ICloudSync.pullNewer(ChannelVisibility.self, name: name, local: visibility, modifiedAt: visibility.modifiedAt, sync: sync) {
            visibility = remote
            if let dir = cacheDirectory { remote.save(to: dir) }
        }
    }

    /// Signed in: the login goes to iCloud if it is not there yet (logins from before sync).
    /// Signed out: what iCloud has is offered on the login screen.
    func refreshSyncedLogins() async {
        await ICloudSync.refreshLogins(logins, available: { iCloudAvailable = $0 },
                                       credentials: credentials, offerXtream: true, offeredXtream: { syncedXtream = $0 },
                                       jellyfinLogin: jellyfin.login, jellyfinSignedIn: jellyfin.session != nil,
                                       offeredJellyfin: { syncedJellyfin = $0 })
    }
}
