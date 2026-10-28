import Foundation
import Testing
@testable import FernsyCore

/// iCloud sync of settings and choices (icloud-sync 2.1): two devices share one store.
@MainActor
struct SyncStoreTests {
    final class FakeStore: SyncBacking {
        var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
        func synchronize() -> Bool { true }
    }

    private let keys = ["library.favorites", "tracks.audioLanguage"]

    private func device(_ name: String, _ store: FakeStore) -> (SyncStore, UserDefaults) {
        let suite = "SyncStoreTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (SyncStore(backing: store, defaults: defaults, keys: keys), defaults)
    }

    @Test func aChangeReachesTheOtherDevice() {
        let store = FakeStore()
        let (mac, macDefaults) = device("mac", store)
        let (tv, tvDefaults) = device("tv", store)
        mac.start(notifications: NotificationCenter())
        tv.start(notifications: NotificationCenter())
        macDefaults.set(["live:101"], forKey: "library.favorites")
        mac.pushLocalChanges()
        var changed: Set<String> = []
        tv.onChange = { changed = $0 }
        tv.pullAll()
        #expect(tvDefaults.stringArray(forKey: "library.favorites") == ["live:101"])
        #expect(changed == ["d.library.favorites"])
    }

    /// The films and series switches (tvos-vod-switch): a Bool arrives, and writing the same value
    /// back (as the app's didSet does) sends nothing new.
    @Test func aSwitchReachesTheOtherDeviceOnce() {
        let store = FakeStore()
        let keys = [LibraryRules.seriesSwitchKey]
        let macDefaults = UserDefaults(suiteName: "SyncStoreTests.mac.\(UUID().uuidString)")!
        let tvDefaults = UserDefaults(suiteName: "SyncStoreTests.tv.\(UUID().uuidString)")!
        let mac = SyncStore(backing: store, defaults: macDefaults, keys: keys)
        let tv = SyncStore(backing: store, defaults: tvDefaults, keys: keys)
        mac.start(notifications: NotificationCenter())
        tv.start(notifications: NotificationCenter())
        macDefaults.set(false, forKey: LibraryRules.seriesSwitchKey)
        mac.pushLocalChanges()
        var changed: Set<String> = []
        tv.onChange = { changed = $0 }
        tv.pullAll()
        #expect(tvDefaults.object(forKey: LibraryRules.seriesSwitchKey) as? Bool == false)
        #expect(changed == ["d." + LibraryRules.seriesSwitchKey])
        let sent = (store.values["d." + LibraryRules.seriesSwitchKey] as? [String: Any])?["t"] as? Date
        tvDefaults.set(false, forKey: LibraryRules.seriesSwitchKey)
        tv.pushLocalChanges()
        #expect((store.values["d." + LibraryRules.seriesSwitchKey] as? [String: Any])?["t"] as? Date == sent)
    }

    @Test func theNewerChangeWins() {
        let store = FakeStore()
        let (mac, macDefaults) = device("mac", store)
        let (tv, tvDefaults) = device("tv", store)
        mac.start(notifications: NotificationCenter())
        tv.start(notifications: NotificationCenter())
        macDefaults.set("de", forKey: "tracks.audioLanguage")
        mac.pushLocalChanges()
        tv.pullAll()
        tvDefaults.set("en", forKey: "tracks.audioLanguage")
        tv.pushLocalChanges()
        mac.pullAll()
        #expect(macDefaults.string(forKey: "tracks.audioLanguage") == "en")
        // The Mac's older value does not come back.
        tv.pullAll()
        #expect(tvDefaults.string(forKey: "tracks.audioLanguage") == "en")
    }

    @Test func valuesFromBeforeSyncAreSentOnce() {
        let store = FakeStore()
        let (mac, macDefaults) = device("mac", store)
        macDefaults.set(["live:7"], forKey: "library.favorites")
        mac.start(notifications: NotificationCenter())
        #expect((store.values["d.library.favorites"] as? [String: Any])?["v"] as? [String] == ["live:7"])
    }

    @Test func nothingMovesWhileSyncIsOff() {
        let store = FakeStore()
        let (mac, macDefaults) = device("mac", store)
        let (tv, tvDefaults) = device("tv", store)
        tv.isEnabled = false
        mac.start(notifications: NotificationCenter())
        tv.start(notifications: NotificationCenter())
        macDefaults.set(["live:1"], forKey: "library.favorites")
        mac.pushLocalChanges()
        tv.pullAll()
        #expect(tvDefaults.stringArray(forKey: "library.favorites") == nil)
        tvDefaults.set(["live:2"], forKey: "library.favorites")
        tv.pushLocalChanges()
        #expect((store.values["d.library.favorites"] as? [String: Any])?["v"] as? [String] == ["live:1"])
    }

    @Test func codableValuesByDate() {
        let store = FakeStore()
        let (mac, _) = device("mac", store)
        let (tv, _) = device("tv", store)
        var hidden = ChannelVisibility()
        hidden.hiddenChannels = [101]
        hidden.modifiedAt = Date(timeIntervalSince1970: 2000)
        let name = SyncStore.accountName("http://example.com|demo", "visibility")
        mac.push(hidden, as: name, modifiedAt: hidden.modifiedAt)
        #expect(tv.pull(ChannelVisibility.self, name: name, newerThan: Date(timeIntervalSince1970: 1000))?.hiddenChannels == [101])
        #expect(tv.pull(ChannelVisibility.self, name: name, newerThan: Date(timeIntervalSince1970: 3000)) == nil)
        // A newer format from a later app version is left alone.
        store.values[name] = ["v": Data(), "t": Date(), "version": 2] as [String: Any]
        #expect(tv.pull(ChannelVisibility.self, name: name, newerThan: .distantPast) == nil)
        #expect(name.utf8.count <= 64)
    }

    @Test func resumePositionsMergePerItem() {
        let store = FakeStore()
        let (mac, macDefaults) = device("mac", store)
        let (tv, tvDefaults) = device("tv", store)
        let macResume = ResumeStore(defaults: macDefaults), tvResume = ResumeStore(defaults: tvDefaults)
        mac.start(notifications: NotificationCenter())
        tv.start(notifications: NotificationCenter())
        let earlier = Date().addingTimeInterval(-3600)
        _ = macResume.save("movie.1", position: 600, duration: 6000, at: earlier)
        _ = tvResume.save("movie.2", position: 900, duration: 5000, at: earlier)
        mac.pushLocalChanges()
        tv.pushLocalChanges()
        mac.pullAll()
        tv.pullAll()
        #expect(macResume.position("movie.2") == 900)
        #expect(tvResume.position("movie.1") == 600)
        // Later on the Apple TV: the newer position wins on the Mac.
        _ = tvResume.save("movie.1", position: 2520, duration: 6000, at: Date())
        tv.pushLocalChanges()
        mac.pullAll()
        #expect(macResume.position("movie.1") == 2520)
        // Older than 90 days: kept on the device, not sent.
        _ = macResume.save("movie.3", position: 300, duration: 6000, at: Date().addingTimeInterval(-100 * 86400))
        mac.pushLocalChanges()
        tv.pullAll()
        #expect(tvResume.position("movie.3") == 0)
    }

    @Test func aFinishedFilmStaysFinished() {
        var position = ResumeEntry(position: 600, duration: 6000, at: Date(timeIntervalSince1970: 1000), watched: false)
        let finished = ResumeEntry(position: 0, duration: 0, at: .distantPast, watched: true)
        #expect(ResumeEntry.merge(["m": finished], ["m": position])["m"] == finished)
        // Watching it again after it was finished keeps the new position.
        position.watched = true
        #expect(ResumeEntry.merge(["m": finished], ["m": position])["m"]?.position == 600)
    }
}
