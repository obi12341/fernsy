import Foundation
import Testing
@testable import FernsyCore

/// The Jellyfin overview's rows (tvos-jellyfin-overview 1.3): each row's filter and order, empty
/// rows left out, the spotlight without repeats.
struct JellyfinOverviewTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// An item as the apps cache it; `minutes` is the runtime (for a series, per episode).
    private func item(_ id: String, series: Bool = false, rating: Double? = nil, year: Int? = nil, genres: [String] = [],
                      minutes: Int? = nil, played: Bool = false, favorite: Bool = false, left: Int? = nil, total: Int? = nil,
                      lastPlayed: String? = nil, backdrop: Bool = true, added: String = "2026-01-01") -> JFItem {
        var json: [String: Any] = ["id": id, "name": id, "type": series ? "Series" : "Movie", "genres": genres, "dateCreated": added]
        if let rating { json["communityRating"] = rating }
        if let year { json["productionYear"] = year }
        if let minutes { json["runTimeTicks"] = Int64(minutes) * 600_000_000 }
        if backdrop { json["backdropImageTags"] = ["b"] }
        if let total { json["recursiveItemCount"] = total }
        var user: [String: Any] = ["played": played, "isFavorite": favorite]
        if let left { user["unplayedItemCount"] = left }
        if let lastPlayed { user["lastPlayedDate"] = lastPlayed }
        json["userData"] = user
        return try! JSONDecoder().decode(JFItem.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func spotlightTakesUnwatchedWellRatedFilmsWithABackdrop() {
        let films = [item("good", rating: 8), item("watched", rating: 9, played: true), item("weak", rating: 5),
                     item("noBackdrop", rating: 8.5, backdrop: false)]
        let overview = JellyfinOverview.build(films: films, series: [], now: now)
        #expect(overview.spotlightCandidates.map(\.id) == ["good"])
        // Another suggestion avoids the recent ones while others are left.
        let pool = [item("a", rating: 8), item("b", rating: 8)]
        #expect(JellyfinOverview.pick(from: pool, avoiding: ["a"])?.id == "b")
        #expect(JellyfinOverview.pick(from: pool, avoiding: ["a", "b"]) != nil)
    }

    @Test func spotlightFallsBackWithoutRatings() {
        let overview = JellyfinOverview.build(films: [item("plain"), item("seen", played: true)], series: [], now: now)
        #expect(overview.spotlightCandidates.map(\.id) == ["plain"])
        // Without backdrops: the well-rated unwatched ones, then any unwatched film.
        let bare = JellyfinOverview.build(films: [item("rated", rating: 8, backdrop: false), item("other", backdrop: false)], series: [], now: now)
        #expect(bare.spotlightCandidates.map(\.id) == ["rated"])
        let plain = JellyfinOverview.build(films: [item("other", backdrop: false)], series: [], now: now)
        #expect(plain.spotlightCandidates.map(\.id) == ["other"])
    }

    @Test func rowsFollowTheirRules() {
        let films = [item("top", rating: 8.2, minutes: 130), item("short", rating: 7, minutes: 85),
                     item("shortWeak", rating: 5, minutes: 80), item("fav", rating: 6, favorite: true),
                     item("old", rating: 8, played: true, lastPlayed: "2024-01-01T20:00:00.0000000Z"),
                     item("recent", rating: 8, played: true, lastPlayed: "2027-01-01T20:00:00.0000000Z")]
        let series = [item("almost", series: true, rating: 7, left: 2, total: 10, lastPlayed: "2026-12-01T20:00:00Z"),
                      item("fresh", series: true, rating: 8, left: 10, total: 10),
                      item("many", series: true, rating: 7, left: 6, total: 10)]
        let overview = JellyfinOverview.build(films: films, series: series, now: now)
        #expect(overview.topRated.map(\.id) == ["top", "fresh"])
        #expect(overview.shortAndGood.map(\.id) == ["short"])
        #expect(overview.favorites.map(\.id) == ["fav"])
        #expect(overview.almostDone.map(\.id) == ["almost"])
        #expect(overview.rediscover.map(\.id) == ["old"])
        #expect(overview.filmCount == 6 && overview.seriesCount == 3)
    }

    @Test func tilesNeedThreeTitles() {
        let films = [item("a", rating: 6, year: 1994, genres: ["Comedy"]), item("b", rating: 9, year: 1997, genres: ["Comedy"]),
                     item("c", rating: 7, year: 1999, genres: ["Comedy", "Drama"]), item("d", year: 2021, genres: ["Drama"])]
        let overview = JellyfinOverview.build(films: films, series: [], now: now)
        #expect(overview.genres.map(\.id) == ["genre.Comedy"])
        #expect(overview.genres.first?.items.first?.id == "b")
        #expect(overview.decades.map(\.id) == ["decade.1990"])
    }

    @Test func emptyLibraryHasNoRows() {
        let overview = JellyfinOverview.build(films: [], series: [], now: now)
        #expect(overview.spotlightCandidates.isEmpty && overview.topRated.isEmpty && overview.genres.isEmpty)
        #expect(overview.unwatchedHours == nil)
    }

    @Test func unwatchedHoursCountFilmsAndEpisodesLeft() {
        let overview = JellyfinOverview.build(films: [item("f", minutes: 120), item("seen", minutes: 600, played: true)],
                                              series: [item("s", series: true, minutes: 45, left: 4, total: 8)], now: now)
        #expect(overview.unwatchedHours == 5)
    }
}
