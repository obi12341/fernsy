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
    static var syncAllowed: Bool { !skipKeychain || ProcessInfo.processInfo.environment["IPTV_SYNC"] == "1" }
    static let syncedKeys = [LiveRules.favoritesKey, LiveRules.recentKey, TrackPreferences.audioKey,
                             TrackPreferences.subtitlesKey, Recorder.padBeforeKey, Recorder.padAfterKey,
                             LibraryRules.moviesSwitchKey, LibraryRules.seriesSwitchKey]

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

    /// The logins: CloudKit when sync is allowed. Debug builds' IPTV_TESTICLOUDLOGIN=demo|demo-wrong|
    /// jellyfin puts one in memory, so the launch path runs without iCloud.
    static func makeLogins() -> LoginSync {
        #if DEBUG
        let demo = "https://fernsy-demo.mobilistics.workers.dev"
        // IPTV_TESTICLOUDDELAY=<s>: the lookup takes that long, as CloudKit does on a device.
        let delay = Duration.seconds(Double(ProcessInfo.processInfo.environment["IPTV_TESTICLOUDDELAY"] ?? "") ?? 0)
        switch ProcessInfo.processInfo.environment["IPTV_TESTICLOUDLOGIN"] {
        case "demo": return LoginSync(backing: MemoryLogins(xtream: XtreamCredentials(server: demo, username: "demo", password: "demo"), delay: delay))
        case "demo-wrong": return LoginSync(backing: MemoryLogins(xtream: XtreamCredentials(server: demo, username: "demo", password: "wrong"), delay: delay))
        case "jellyfin":
            return LoginSync(backing: MemoryLogins(jellyfin: .init(server: "http://127.0.0.1:8097", username: "fixture", password: "fixture-pass"), delay: delay))
        default: break
        }
        #endif
        return syncAllowed ? .cloudKit() : LoginSync(backing: nil)
    }

    /// Launched without an account (icloud-auto-signin): signs in with what iCloud has, provider
    /// and Jellyfin each on their own, showing the steps (at least `minimumShown` once something
    /// signed in, until the channels are loaded). What fails stays offered on the login screen,
    /// with the reason if nothing could be signed in.
    private func signInFromICloud() async {
        let started = ContinuousClock.now
        iCloudSteps = [ICloudSignInStep(.found)]
        let found = await logins.launchLogins()
        var failure: Error?
        if found.xtream != nil || found.jellyfin != nil { iCloudSteps.finish(.found) }
        if let xtream = found.xtream {
            let host = xtream.baseURL?.host() ?? xtream.server
            AppLog.info(.app, "iCloud: signing in with the IPTV login at \(host)")
            iCloudSteps.append(ICloudSignInStep(.provider, server: host))
            do {
                try await login(xtream)
                iCloudSteps.finish(.channels)
            } catch {
                failure = error
                syncedXtream = xtream
            }
        }
        if let login = found.jellyfin {
            let host = URL(string: login.server)?.host() ?? login.server
            AppLog.info(.app, "iCloud: signing in with the Jellyfin login at \(host)")
            iCloudSteps.append(ICloudSignInStep(.jellyfin, server: host))
            do {
                try await jellyfin.signIn(server: login.server, username: login.username, password: login.password)
                iCloudSteps.finish(.jellyfin)
            } catch {
                failure = failure ?? error
                syncedJellyfin = login
            }
        }
        let signedIn = credentials != nil || jellyfin.session != nil
        iCloudSignInError = signedIn ? nil : failure?.localizedDescription
        if signedIn {
            // The last checkmark stays a moment, and the screen at least `minimumShown`.
            try? await Task.sleep(for: .milliseconds(400))
            try? await Task.sleep(until: started + ICloudSignInStep.minimumShown)
        }
        signingInFromICloud = false
    }

    /// Values from another device: favourites, recently watched and the films and series switches
    /// again from UserDefaults (track languages and padding are read where they are used), hidden
    /// channels from the store.
    private func syncArrived(_ names: Set<String>) {
        if names.contains("d." + LiveRules.favoritesKey) {
            favorites = Set(UserDefaults.standard.stringArray(forKey: LiveRules.favoritesKey) ?? [])
        }
        if names.contains("d." + LiveRules.recentKey) {
            recentChannels = UserDefaults.standard.array(forKey: LiveRules.recentKey) as? [Int] ?? []
        }
        if names.contains("resume") { resumeRevision += 1 }
        // Films or series switched on another device: as if switched here (drops or downloads).
        if names.contains("d." + LibraryRules.moviesSwitchKey) {
            showsIPTVMovies = UserDefaults.standard.object(forKey: LibraryRules.moviesSwitchKey) as? Bool ?? true
        }
        if names.contains("d." + LibraryRules.seriesSwitchKey) {
            showsIPTVSeries = UserDefaults.standard.object(forKey: LibraryRules.seriesSwitchKey) as? Bool ?? true
        }
        pullVisibility()
    }

    /// The account's hidden categories and channels: the newer of this Mac's and iCloud's; sent
    /// once if iCloud has none yet.
    func pullVisibility() {
        guard let key = credentials?.accountKey else { return }
        let name = SyncStore.accountName(key, "visibility")
        if let remote = sync.pull(ChannelVisibility.self, name: name, newerThan: visibility.modifiedAt) {
            visibility = remote
            if let dir = cacheDirectory { remote.save(to: dir) }
        } else if !sync.hasValue(name) && visibility.modifiedAt.timeIntervalSince1970 > 0 {
            sync.push(visibility, as: name, modifiedAt: visibility.modifiedAt)
        }
    }

    /// Signed in: the login goes to iCloud if it is not there yet (logins from before sync).
    /// Signed out: what iCloud has is offered on the login screen.
    func refreshSyncedLogins() async {
        iCloudAvailable = await logins.isAvailable()
        guard iCloudAvailable else { AppLog.info(.app, "iCloud: not available"); return }
        if let credentials {
            if await logins.xtream() == nil { await logins.save(credentials) }
        } else {
            syncedXtream = await logins.xtream()
            if let login = syncedXtream { AppLog.info(.app, "iCloud: offers the IPTV login at \(login.baseURL?.host() ?? login.server)") }
        }
        if let login = jellyfin.login {
            if await logins.jellyfin() == nil { await logins.save(login) }
        } else if jellyfin.session == nil {
            syncedJellyfin = await logins.jellyfin()
            if let login = syncedJellyfin { AppLog.info(.app, "iCloud: offers the Jellyfin login at \(URL(string: login.server)?.host() ?? login.server)") }
        }
    }
}
