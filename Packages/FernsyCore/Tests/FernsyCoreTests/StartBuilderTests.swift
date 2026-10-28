import Foundation
import Testing
@testable import FernsyCore

/// Start's rows (mac-start-pages 1.1): the rules both apps share, each row's selection and order,
/// rows without enough entries left out.
struct StartBuilderTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: [String: Any]) -> T {
        try! JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func movie(_ id: Int, category: String = "1", added: Int = 1_000, rating: Double? = nil, poster: Bool = true) -> Movie {
        var json: [String: Any] = ["stream_id": id, "name": "Film \(id)", "category_id": category, "added": "\(added)",
                                   "container_extension": "mp4"]
        if let rating { json["rating"] = "\(rating)" }
        if poster { json["stream_icon"] = "https://img.test/\(id).png" }
        return decode(Movie.self, json)
    }

    private func series(_ id: Int, category: String = "20", modified: Int = 1_000) -> Series {
        decode(Series.self, ["series_id": id, "name": "Series \(id)", "category_id": category, "last_modified": "\(modified)"])
    }

    private func channel(_ id: Int) -> LiveChannel {
        decode(LiveChannel.self, ["stream_id": id, "name": "Channel \(id)"])
    }

    private func jellyfin(_ id: String, type: String = "Movie", genres: [String] = [], created: String = "2026-01-01T00:00:00Z") -> JFItem {
        decode(JFItem.self, ["id": id, "name": id, "type": type, "genres": genres, "dateCreated": created])
    }

    @Test func recentlyAddedInterleavesSourcesByDate() {
        var builder = StartBuilder()
        builder.movies = [movie(1, added: 100), movie(2, added: 300)]
        builder.series = [series(800, modified: 200)]
        builder.jellyfinLatestFilms = [jellyfin("jf1", created: "1970-01-01T00:06:40Z")]  // 400 s
        #expect(builder.recentlyAdded().map(\.id) == ["jf.jf1", "movie:2", "series:800", "movie:1"])
    }

    @Test func spotlightIsTheNewestFilm() {
        var builder = StartBuilder()
        builder.series = [series(800, modified: 900)]
        builder.movies = [movie(1, added: 100), movie(2, added: 500)]
        #expect(builder.catalogRows().spotlight?.id == "movie:2")
    }

    @Test func categoriesNeedThreeTitlesAndTakeTheLargest() {
        var builder = StartBuilder()
        builder.movieCategories = [XCategory(id: "1", name: "Action"), XCategory(id: "2", name: "Drama"), XCategory(id: "3", name: "Tiny")]
        builder.movies = (1...5).map { movie($0, category: "1", added: $0) } + (6...8).map { movie($0, category: "2") } + [movie(9, category: "3")]
        builder.jellyfinFilms = ["a", "b", "c"].map { jellyfin($0, genres: ["Comedy"]) } + [jellyfin("d", genres: ["Horror"])]
        let rows = builder.catalogRows().categories
        #expect(rows.map(\.id) == ["films.1", "films.2", "jf.genre.Comedy"])
        #expect(rows.first?.entries.first?.id == "movie:5")
    }

    @Test func bestRatedNeedsSevenAndAPoster() {
        var builder = StartBuilder()
        builder.movies = [movie(1, rating: 8.5), movie(2, rating: 6.9), movie(3, rating: 9, poster: false), movie(4, rating: 7)]
        #expect(builder.catalogRows().bestRated.map(\.id) == ["movie:1", "movie:4"])
    }

    @Test func continueWatchingNewestFirstAcrossSources() {
        let resume = ResumeStore(defaults: nil)
        _ = resume.save(ResumeStore.movieKey(1), position: 600, duration: 5_400, at: Date(timeIntervalSince1970: 100))
        let recording = StartRecording(id: UUID(), title: "Show", channelId: 101, channelName: "Channel 101",
                                       start: Date(timeIntervalSince1970: 0), recordStart: Date(timeIntervalSince1970: 0),
                                       recordEnd: Date(timeIntervalSince1970: 3_600), finished: true, failed: false)
        _ = resume.save(ResumeStore.recordingKey(recording.id), position: 900, duration: 3_600, at: Date(timeIntervalSince1970: 200))
        var builder = StartBuilder()
        builder.movies = [movie(1)]
        builder.resume = resume
        builder.recordings = [recording]
        let entries = builder.continueWatching()
        #expect(entries.map(\.id) == [ResumeStore.recordingKey(recording.id), "movie.1"])
        #expect(entries.first?.progress == 0.25)
        if case .recording(let id) = entries.first?.open { #expect(id == recording.id) } else { Issue.record("not a recording") }
    }

    @Test func liveChannelsFallBackFromFavoritesToRecentToAll() {
        let all = (1...20).map(channel)
        #expect(StartBuilder.liveChannels(favorites: [all[3]], recent: [all[5]], all: all).source == .favorites)
        #expect(StartBuilder.liveChannels(favorites: [], recent: [all[5]], all: all).channels.map(\.id) == [6])
        let fallback = StartBuilder.liveChannels(favorites: [], recent: [], all: all)
        #expect(fallback.source == .all && fallback.channels.count == 12)
    }

    @Test func tonightIsPrimeTimeThenTheNextTwoHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 18))!
        func at(_ hour: Int, _ minute: Int = 0) -> Date { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)! }
        let show = EPGEntry(id: "a", title: "Prime", description: "", start: at(20, 15), end: at(21, 45))
        let late = EPGEntry(id: "b", title: "Late", description: "", start: at(22, 30), end: at(23, 30))
        let guide: (Int) -> [EPGEntry] = { _ in [show, late] }
        let evening = StartBuilder.tonight(on: [channel(1)], guide: guide, now: at(18), calendar: calendar)
        #expect(evening.shows.map(\.show.title) == ["Prime"])
        let night = StartBuilder.tonight(on: [channel(1)], guide: guide, now: at(21, 40), calendar: calendar)
        #expect(night.shows.map(\.show.title) == ["Late"])
    }
}
