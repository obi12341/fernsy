import FernsyCore
import Foundation

/// The rules of icloud-sync that the Mac and the Apple TV share (code-structure-cleanup 3.1):
/// which keys sync, when sync is allowed, the logins' backing, applying what arrives, signing in
/// with iCloud's logins at launch and offering them later. Each app passes in what differs: how
/// it signs in to the provider and which account values it pulls. In FernsyPlayer because the
/// synced keys include the recorder's padding.
public enum ICloudSync {
    @MainActor public static let syncedKeys = [LiveRules.favoritesKey, LiveRules.recentKey, TrackPreferences.audioKey,
                                    TrackPreferences.subtitlesKey, Recorder.padBeforeKey, Recorder.padAfterKey,
                                    LibraryRules.moviesSwitchKey, LibraryRules.seriesSwitchKey]

    /// Keychain-less runs (UI tests, debug runs) sync only with IPTV_SYNC=1.
    public static func allowed(skipKeychain: Bool) -> Bool {
        !skipKeychain || ProcessInfo.processInfo.environment["IPTV_SYNC"] == "1"
    }

    /// The logins: CloudKit when sync is allowed. Debug builds' IPTV_TESTICLOUDLOGIN=demo|demo-wrong|
    /// jellyfin puts one in memory, so the launch path runs without iCloud.
    public static func makeLogins(allowed: Bool) -> LoginSync {
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
        return allowed ? .cloudKit() : LoginSync(backing: nil)
    }

    /// What arrived from another device, read again from UserDefaults: favourites, recently
    /// watched, resume positions and the films and series switches (nil: unchanged).
    public struct Arrived {
        public var favorites: Set<String>?
        public var recentChannels: [Int]?
        public var resume = false
        public var showsMovies: Bool?
        public var showsSeries: Bool?
    }

    public static func arrived(_ names: Set<String>, defaults: UserDefaults = .standard) -> Arrived {
        var result = Arrived()
        if names.contains("d." + LiveRules.favoritesKey) { result.favorites = Set(defaults.stringArray(forKey: LiveRules.favoritesKey) ?? []) }
        if names.contains("d." + LiveRules.recentKey) { result.recentChannels = defaults.array(forKey: LiveRules.recentKey) as? [Int] ?? [] }
        result.resume = names.contains("resume")
        if names.contains("d." + LibraryRules.moviesSwitchKey) { result.showsMovies = defaults.object(forKey: LibraryRules.moviesSwitchKey) as? Bool ?? true }
        if names.contains("d." + LibraryRules.seriesSwitchKey) { result.showsSeries = defaults.object(forKey: LibraryRules.seriesSwitchKey) as? Bool ?? true }
        return result
    }

    /// An account value (hidden channels, pinned categories): iCloud's when it is newer than the
    /// local one (returned), else the local one is sent once if iCloud has none yet (nil).
    @MainActor
    public static func pullNewer<T: Codable>(_ type: T.Type, name: String, local: T, modifiedAt: Date, sync: SyncStore) -> T? {
        if let remote = sync.pull(T.self, name: name, newerThan: modifiedAt) { return remote }
        if !sync.hasValue(name) && modifiedAt.timeIntervalSince1970 > 0 { sync.push(local, as: name, modifiedAt: modifiedAt) }
        return nil
    }

    /// Launched without an account (icloud-auto-signin): signs in with what iCloud has, provider
    /// and Jellyfin each on their own, showing the steps (at least `minimumShown` once something
    /// signed in, until the channels are loaded). The steps are the model's own (`steps`, set
    /// through `setSteps`): its sign-in changes them too. The sign-in closures return the failure's
    /// text (and keep the failed login offered); the result is the error to show when nothing
    /// signed in.
    @MainActor
    public static func signInAtLaunch(logins: LoginSync, steps: () -> [ICloudSignInStep], setSteps: ([ICloudSignInStep]) -> Void,
                                      signInIPTV: (XtreamCredentials) async -> String?,
                                      signInJellyfin: (LoginSync.JellyfinLogin) async -> String?,
                                      isSignedIn: () -> Bool) async -> String? {
        func change(_ edit: (inout [ICloudSignInStep]) -> Void) {
            var current = steps()
            edit(&current)
            setSteps(current)
        }
        let started = ContinuousClock.now
        setSteps([ICloudSignInStep(.found)])
        let found = await logins.launchLogins()
        var failure: String?
        if found.xtream != nil || found.jellyfin != nil { change { $0.finish(.found) } }
        if let login = found.xtream {
            let host = login.baseURL?.host() ?? login.server
            AppLog.info(.app, "iCloud: signing in with the IPTV login at \(host)")
            change { $0.append(ICloudSignInStep(.provider, server: host)) }
            if let message = await signInIPTV(login) { failure = message } else { change { $0.finish(.channels) } }
        }
        if let login = found.jellyfin {
            let host = URL(string: login.server)?.host() ?? login.server
            AppLog.info(.app, "iCloud: signing in with the Jellyfin login at \(host)")
            change { $0.append(ICloudSignInStep(.jellyfin, server: host)) }
            if let message = await signInJellyfin(login) { failure = failure ?? message } else { change { $0.finish(.jellyfin) } }
        }
        let signedIn = isSignedIn()
        if signedIn {
            // The last checkmark stays a moment, and the screen at least `minimumShown`.
            try? await Task.sleep(for: .milliseconds(400))
            try? await Task.sleep(until: started + ICloudSignInStep.minimumShown)
        }
        return signedIn ? nil : failure
    }

    /// Signed in: the login goes to iCloud if it is not there yet (logins from before sync).
    /// Without an account: what iCloud has is offered on the login or welcome screen, the IPTV
    /// login only when `offerXtream`.
    @MainActor
    public static func refreshLogins(_ logins: LoginSync, available: (Bool) -> Void,
                                     credentials: XtreamCredentials?, offerXtream: Bool, offeredXtream: (XtreamCredentials?) -> Void,
                                     jellyfinLogin: LoginSync.JellyfinLogin?, jellyfinSignedIn: Bool,
                                     offeredJellyfin: (LoginSync.JellyfinLogin?) -> Void) async {
        let isAvailable = await logins.isAvailable()
        available(isAvailable)
        guard isAvailable else { AppLog.info(.app, "iCloud: not available"); return }
        if let credentials {
            if await logins.xtream() == nil { await logins.save(credentials) }
        } else if offerXtream {
            let login = await logins.xtream()
            offeredXtream(login)
            if let login { AppLog.info(.app, "iCloud: offers the IPTV login at \(login.baseURL?.host() ?? login.server)") }
        }
        if let login = jellyfinLogin {
            if await logins.jellyfin() == nil { await logins.save(login) }
        } else if !jellyfinSignedIn {
            let login = await logins.jellyfin()
            offeredJellyfin(login)
            if let login { AppLog.info(.app, "iCloud: offers the Jellyfin login at \(URL(string: login.server)?.host() ?? login.server)") }
        }
    }
}
