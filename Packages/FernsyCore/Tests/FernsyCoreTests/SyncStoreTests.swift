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

/// Coming back to the front and the series of started episodes (continue-watching-fresh 1.1–1.3).
@MainActor
struct SyncRefreshAndSeriesTests {
    typealias FakeStore = SyncStoreTests.FakeStore

    private func device(_ name: String, _ store: FakeStore) -> (SyncStore, UserDefaults, ResumeStore) {
        let defaults = UserDefaults(suiteName: "SyncRefreshAndSeriesTests.\(name).\(UUID().uuidString)")!
        return (SyncStore(backing: store, defaults: defaults, keys: []), defaults, ResumeStore(defaults: defaults))
    }

    @Test func refreshTakesWhatArrivedWithoutANotification() {
        let store = FakeStore()
        let (mac, _, macResume) = device("mac", store)
        let (phone, _, phoneResume) = device("phone", store)
        mac.start(notifications: NotificationCenter())
        phone.start(notifications: NotificationCenter())
        macResume.save("movie.500", position: 1200, duration: 3000)
        mac.pushLocalChanges()
        // No notification reaches the phone: it only knows after asking again.
        #expect(phoneResume.position("movie.500") == 0)
        var changed: Set<String> = []
        phone.onChange = { changed = $0 }
        phone.refresh()
        #expect(phoneResume.position("movie.500") == 1200)
        #expect(changed.contains("resume"))
        phone.refresh()
        #expect(changed.isEmpty, "a second refresh found something again: \(changed)")
    }

    @Test func refreshTakesNothingWithSyncOff() {
        let store = FakeStore()
        let (mac, _, macResume) = device("mac", store)
        let (phone, _, phoneResume) = device("phone", store)
        mac.start(notifications: NotificationCenter())
        phone.start(notifications: NotificationCenter())
        phone.isEnabled = false
        macResume.save("movie.500", position: 1200, duration: 3000)
        mac.pushLocalChanges()
        phone.refresh()
        #expect(phoneResume.position("movie.500") == 0)
    }

    @Test func theSeriesOfAnEpisodeIsKept() {
        let resume = ResumeStore(defaults: UserDefaults(suiteName: "series.\(UUID().uuidString)")!)
        #expect(resume.series(ofEpisode: "00101") == nil)
        resume.setSeries(800, forEpisode: "00101")
        #expect(resume.series(ofEpisode: "00101") == 800)
        let memory = ResumeStore(defaults: nil)
        memory.setSeries(800, forEpisode: "00101")
        #expect(memory.series(ofEpisode: "00101") == 800)
    }

    /// A position saved by an older version gets its series when the series' list is loaded;
    /// episodes never played do not.
    @Test func aLoadedListGivesStartedEpisodesTheirSeries() {
        let resume = ResumeStore(defaults: UserDefaults(suiteName: "adopt.\(UUID().uuidString)")!)
        resume.save("episode.00101", position: 300, duration: 1500)
        resume.save("episode.00102", position: 1490, duration: 1500)  // watched
        #expect(resume.adoptSeries(800, episodes: ["00100", "00101", "00102"]) == 2)
        #expect(resume.series(ofEpisode: "00101") == 800)
        #expect(resume.series(ofEpisode: "00102") == 800)
        #expect(resume.series(ofEpisode: "00100") == nil)
        #expect(resume.adoptSeries(800, episodes: ["00101"]) == 0)
    }

    /// The new value is not read as a position.
    @Test func positionsReadTheSameWithTheSeriesStored() {
        let defaults = UserDefaults(suiteName: "read.\(UUID().uuidString)")!
        let resume = ResumeStore(defaults: defaults)
        resume.save("episode.00101", position: 300, duration: 1500)
        resume.save("movie.500", position: 600, duration: 3000)
        let before = (ResumeEntry.read(defaults), resume.started(prefix: "episode."), resume.started(prefix: ""))
        resume.setSeries(800, forEpisode: "00101")
        #expect(ResumeEntry.read(defaults) == before.0)
        #expect(resume.started(prefix: "episode.") == before.1)
        #expect(resume.started(prefix: "") == before.2)
    }

    @Test func theSeriesReachesTheOtherDevice() {
        let store = FakeStore()
        let (mac, _, macResume) = device("mac", store)
        let (phone, _, phoneResume) = device("phone", store)
        mac.start(notifications: NotificationCenter())
        phone.start(notifications: NotificationCenter())
        macResume.save("episode.00101", position: 300, duration: 1500)
        macResume.setSeries(800, forEpisode: "00101")
        mac.pushLocalChanges()
        var changed: Set<String> = []
        phone.onChange = { changed = $0 }
        phone.refresh()
        #expect(phoneResume.series(ofEpisode: "00101") == 800)
        #expect(changed.contains("resumeSeries"))
    }

    /// A device on an older version decodes `resume` into its four fields, merges its own and
    /// writes the whole value back; it never touches `resumeSeries`.
    @Test func anOlderDeviceNeitherLosesPositionsNorTheSeries() {
        let store = FakeStore()
        let (mac, _, macResume) = device("mac", store)
        mac.start(notifications: NotificationCenter())
        macResume.save("episode.00101", position: 300, duration: 1500)
        macResume.setSeries(800, forEpisode: "00101")
        mac.pushLocalChanges()

        // The older device: its own film, written back as it would.
        var old = ResumeEntry.decode(store.values["resume"])
        old = ResumeEntry.merge(old, ["movie.500": ResumeEntry(position: 900, duration: 3000, at: Date(), watched: false)])
        store.values["resume"] = ResumeEntry.encode(old)

        let (phone, _, phoneResume) = device("phone", store)
        phone.start(notifications: NotificationCenter())
        #expect(phoneResume.series(ofEpisode: "00101") == 800)
        #expect(phoneResume.position("episode.00101") == 300)
        #expect(phoneResume.position("movie.500") == 900)
        #expect(ResumeEntry.decode(store.values["resume"])["movie.500"]?.position == 900)
    }

    /// Only episodes with a position in iCloud are sent: one that is only watched (or never
    /// played) on this device keeps its series here alone.
    @Test func onlyEpisodesWithAPositionAreSent() {
        let store = FakeStore()
        let (mac, _, macResume) = device("mac", store)
        mac.start(notifications: NotificationCenter())
        macResume.save("episode.00101", position: 300, duration: 1500)
        macResume.save("episode.00102", position: 1490, duration: 1500)
        macResume.setSeries(800, forEpisode: "00101")
        macResume.setSeries(800, forEpisode: "00102")
        macResume.setSeries(801, forEpisode: "00200")
        mac.pushLocalChanges()
        #expect(store.values["resumeSeries"] as? [String: Int] == ["00101": 800])
    }

    /// Watched to the end on one device: finished on the other, and gone from Continue Watching;
    /// started again there, the new position wins everywhere (continue-watching-fresh 1.4).
    @Test func finishedOnOneDeviceIsFinishedOnTheOther() {
        let store = FakeStore()
        let (mac, _, macResume) = device("mac", store)
        let (phone, _, phoneResume) = device("phone", store)
        mac.start(notifications: NotificationCenter())
        phone.start(notifications: NotificationCenter())
        phoneResume.save("movie.500", position: 1200, duration: 3000)
        phone.pushLocalChanges()
        mac.refresh()
        #expect(macResume.position("movie.500") == 1200)

        macResume.save("movie.500", position: 2990, duration: 3000)
        mac.pushLocalChanges()
        phone.refresh()
        #expect(phoneResume.position("movie.500") == 0)
        #expect(phoneResume.isWatched("movie.500"))
        var builder = StartBuilder()
        builder.movies = [try! JSONDecoder().decode(Movie.self, from: Data(#"{"stream_id": 500, "name": "Stardust", "container_extension": "mp4"}"#.utf8))]
        builder.resume = phoneResume
        #expect(builder.continueWatching().isEmpty)

        phoneResume.save("movie.500", position: 300, duration: 3000)
        phone.pushLocalChanges()
        mac.refresh()
        #expect(macResume.position("movie.500") == 300)
        #expect(phoneResume.position("movie.500") == 300)
    }

    /// Finished long ago and not in iCloud: not sent.
    @Test func anOldFinishedItemIsNotSent() {
        let store = FakeStore()
        let (mac, _, macResume) = device("mac", store)
        mac.start(notifications: NotificationCenter())
        macResume.save("movie.501", position: 2990, duration: 3000)
        mac.pushLocalChanges()
        #expect(ResumeEntry.decode(store.values["resume"])["movie.501"] == nil)
    }
}

