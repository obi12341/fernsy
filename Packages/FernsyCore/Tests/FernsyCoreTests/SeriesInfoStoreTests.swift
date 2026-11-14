import Foundation
import Testing
@testable import FernsyCore

/// Episode lists kept on the device and the series Start still needs (continue-watching-fresh 2.1, 2.2).
struct SeriesInfoStoreTests {
    /// The demo server's answer, recorded for FernsySharedTests.
    private static func fixture() throws -> Data {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: tests.appendingPathComponent("FernsySharedTests/Fixtures/xtream/get_series_info.json"))
    }

    private func store() -> SeriesInfoStore {
        SeriesInfoStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("series-info-\(UUID().uuidString)"))
    }

    @Test func aSavedListLoadsTheSame() throws {
        let data = try Self.fixture()
        let store = store()
        let original = try JSONDecoder().decode(SeriesInfo.self, from: data)
        #expect(store.save(data, for: 800) != nil)
        let loaded = try #require(store.load(800))
        #expect(loaded.seasons.keys.sorted() == original.seasons.keys.sorted())
        #expect(loaded.seasons.values.flatMap { $0 }.map(\.id).sorted() == original.seasons.values.flatMap { $0 }.map(\.id).sorted())
        #expect(store.load(801) == nil)
    }

    @Test func aDamagedFileLoadsAsNothingAndIsRemoved() throws {
        let store = store()
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        let file = store.folder.appendingPathComponent("800.json")
        try Data("<html>".utf8).write(to: file)
        #expect(store.load(800) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(store.save(Data("<html>".utf8), for: 800) == nil)
    }

    @Test func removingAllLeavesNoList() throws {
        let store = store()
        store.save(try Self.fixture(), for: 800)
        store.removeAll()
        #expect(store.load(800) == nil)
    }

    private func resume(_ episodes: [(id: String, series: Int?, at: Date)]) -> ResumeStore {
        let resume = ResumeStore(defaults: UserDefaults(suiteName: "started.\(UUID().uuidString)")!)
        for e in episodes {
            resume.save("episode.\(e.id)", position: 300, duration: 1500, at: e.at)
            if let series = e.series { resume.setSeries(series, forEpisode: e.id) }
        }
        return resume
    }

    @Test func newestFirstEachOnce() {
        let now = Date()
        let resume = resume([("a", 800, now.addingTimeInterval(-300)), ("b", 801, now), ("c", 800, now.addingTimeInterval(-100))])
        #expect(StartedEpisodes.missingSeries(resume: resume, known: [], catalog: [800, 801]) == [801, 800])
    }

    @Test func knownSeriesAndSeriesNotInTheCatalogAreLeftOut() {
        let now = Date()
        let resume = resume([("a", 800, now), ("b", 801, now.addingTimeInterval(-10)), ("c", 802, now.addingTimeInterval(-20)), ("d", nil, now.addingTimeInterval(-30))])
        #expect(StartedEpisodes.missingSeries(resume: resume, known: [800], catalog: [800, 801]) == [801])
    }

    @Test func onlyTheNewestEpisodesCount() {
        let now = Date()
        let episodes = (0..<25).map { (id: "e\($0)", series: Optional(1000 + $0), at: now.addingTimeInterval(-Double($0))) }
        let resume = resume(episodes)
        let missing = StartedEpisodes.missingSeries(resume: resume, known: [], catalog: Set(1000..<1025))
        #expect(missing == Array(1000..<1020))
    }

    /// Continue Watching lists an episode whenever its list is known, as before.
    @Test func aKnownEpisodeIsListed() throws {
        let info = try JSONDecoder().decode(SeriesInfo.self, from: try Self.fixture())
        let episode = try #require(info.seasons.values.flatMap { $0 }.first)
        let show = try JSONDecoder().decode(Series.self, from: Data(#"{"series_id": 800, "name": "Harbour Detectives"}"#.utf8))
        let resume = resume([(episode.id, 800, Date())])
        var builder = StartBuilder()
        builder.series = [show]
        builder.resume = resume
        #expect(builder.continueWatching().isEmpty)
        builder.episodeIndex = SeriesInfo.episodeIndex([800: info]) { $0 == 800 ? show : nil }
        #expect(builder.continueWatching().map(\.id) == ["episode.\(episode.id)"])
    }
}

/// Jellyfin's rows when the app comes to the front: at most once a minute (continue-watching-fresh 3.3).
struct RefreshThrottleTests {
    @Test func atMostOncePerInterval() {
        var throttle = RefreshThrottle(interval: 60)
        let start = Date()
        let answers = [0.0, 10, 59, 61, 62].map { throttle.allow(now: start.addingTimeInterval($0)) }
        #expect(answers == [true, false, false, true, false])
    }
}
