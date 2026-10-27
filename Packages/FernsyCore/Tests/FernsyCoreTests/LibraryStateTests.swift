import Foundation
import Testing
@testable import FernsyCore

/// Resume positions, watched marks, "Neu" and the search order, shared by the Mac and the Apple
/// TV app (catalog, search specs).
struct LibraryStateTests {
    static func defaults() -> UserDefaults {
        let name = "fernsy.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func resumeFollowsTheMacsRules() {
        for store in [ResumeStore(defaults: Self.defaults()), ResumeStore(defaults: nil)] {
            store.save("movie.1", position: 20, duration: 3600)
            #expect(store.position("movie.1") == 0, "under 30 s nothing is kept")
            store.save("movie.1", position: 1200, duration: 3600)
            #expect(store.position("movie.1") == 1200)
            #expect(store.fraction("movie.1") == 1200.0 / 3600)
            #expect(!store.isWatched("movie.1"))
            #expect(store.save("movie.1", position: 3550, duration: 3600))
            #expect(store.isWatched("movie.1"))
            #expect(store.position("movie.1") == 0, "a finished item has no resume position")
        }
    }

    @Test func startedItemsAreNewestFirst() {
        let store = ResumeStore(defaults: Self.defaults())
        let now = Date()
        store.save("movie.1", position: 100, duration: 3600, at: now.addingTimeInterval(-60))
        store.save("movie.2", position: 100, duration: 3600, at: now)
        store.save("episode.9", position: 100, duration: 1800, at: now)
        #expect(store.started(prefix: "movie.") == ["movie.2", "movie.1"])
        #expect(store.lastPlayed("movie.2") != nil)
    }

    /// Positions the Mac stored before `.at` existed still count, after those with a time.
    @Test func olderPositionsWithoutTime() {
        let defaults = Self.defaults()
        defaults.set(500.0, forKey: "resume.movie.7")
        let store = ResumeStore(defaults: defaults)
        store.save("movie.8", position: 100, duration: 3600)
        #expect(store.started(prefix: "movie.") == ["movie.8", "movie.7"])
        #expect(store.position("movie.7") == 500)
    }

    @Test func newMeansAddedWithinTwoWeeks() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(LibraryRules.isNew(added: Int(now.timeIntervalSince1970) - 86_400, now: now))
        #expect(!LibraryRules.isNew(added: Int(now.timeIntervalSince1970) - 20 * 86_400, now: now))
        #expect(!LibraryRules.isNew(added: 0, now: now))
    }

    @Test func searchRanksStartThenWordThenAnywhere() {
        let names = ["Die Kartografin", "Kartenhaus", "Atlas der Karten", "Wildkart"]
        let index = SearchIndex(entries: names.enumerated().map { SearchEntry(source: .movies, index: $0.offset, key: makeSearchKey($0.element)) })
        #expect(index.search(makeSearchKey("kart"))[.movies] == [1, 2, 0, 3])
    }
}
