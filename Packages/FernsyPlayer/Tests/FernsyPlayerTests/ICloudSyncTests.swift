import FernsyCore
import Foundation
import Testing
@testable import FernsyPlayer

/// The sync rules the Mac and the Apple TV share (code-structure-cleanup 3.1): what arrives is
/// read from the defaults, and an account value comes from iCloud when newer, else is sent once.
@MainActor
struct ICloudSyncTests {
    final class FakeStore: SyncBacking {
        var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
        func synchronize() -> Bool { true }
    }

    struct Value: Codable, Equatable { var text: String }

    @Test func arrivedReadsOnlyTheNamedValues() {
        let defaults = UserDefaults(suiteName: "ICloudSyncTests.\(UUID().uuidString)")!
        defaults.set(["live:1"], forKey: LiveRules.favoritesKey)
        defaults.set(false, forKey: LibraryRules.moviesSwitchKey)
        let arrived = ICloudSync.arrived(["d." + LiveRules.favoritesKey, "d." + LibraryRules.moviesSwitchKey, "resume"], defaults: defaults)
        #expect(arrived.favorites == ["live:1"])
        #expect(arrived.showsMovies == false)
        #expect(arrived.resume)
        #expect(arrived.recentChannels == nil)
        #expect(arrived.showsSeries == nil)
    }

    @Test func newerRemoteWinsOlderIsKept() {
        let store = FakeStore()
        let sync = SyncStore(backing: store, defaults: UserDefaults(suiteName: "ICloudSyncTests.\(UUID().uuidString)")!, keys: [])
        let old = Date(timeIntervalSince1970: 1000), new = Date(timeIntervalSince1970: 2000)
        sync.push(Value(text: "remote"), as: "a.visibility", modifiedAt: new)
        #expect(ICloudSync.pullNewer(Value.self, name: "a.visibility", local: Value(text: "local"), modifiedAt: old, sync: sync) == Value(text: "remote"))
        #expect(ICloudSync.pullNewer(Value.self, name: "a.visibility", local: Value(text: "local"), modifiedAt: Date(timeIntervalSince1970: 3000), sync: sync) == nil)
    }

    @Test func localIsSentOnceWhenICloudHasNone() {
        let store = FakeStore()
        let sync = SyncStore(backing: store, defaults: UserDefaults(suiteName: "ICloudSyncTests.\(UUID().uuidString)")!, keys: [])
        #expect(ICloudSync.pullNewer(Value.self, name: "a.pinned", local: Value(text: "local"), modifiedAt: Date(timeIntervalSince1970: 1000), sync: sync) == nil)
        #expect(sync.hasValue("a.pinned"))
        // Never changed here (modified at 0): nothing is sent.
        #expect(ICloudSync.pullNewer(Value.self, name: "b.pinned", local: Value(text: "local"), modifiedAt: Date(timeIntervalSince1970: 0), sync: sync) == nil)
        #expect(!sync.hasValue("b.pinned"))
    }
}
