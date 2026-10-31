import Foundation
import Testing
@testable import FernsyCore

/// The Apple TV's Top Shelf (tvos-top-shelf 2.3, 3.1): the deep links' ids and URLs, and the
/// snapshot the app writes for the extension.
struct TopShelfTests {
    // MARK: Links

    @Test func parsesEveryKindOfId() {
        let uuid = UUID(uuidString: "6F1C2B9A-3D4E-4F50-8A71-92B3C4D5E6F7")!
        #expect(TopShelfLink.Item(id: "movie:500") == .movie(500))
        #expect(TopShelfLink.Item(id: "episode:800:7041") == .episode(series: 800, episode: "7041"))
        #expect(TopShelfLink.Item(id: "jellyfin:a1b2c3") == .jellyfin("a1b2c3"))
        #expect(TopShelfLink.Item(id: "live:101") == .live(101))
        #expect(TopShelfLink.Item(id: "recording:\(uuid.uuidString)") == .recording(uuid))
    }

    @Test func refusesMalformedIds() {
        for id in ["", "movie", "movie:", "movie:abc", "movie:1:2", "episode:800", "episode:x:1", "episode:800:",
                   "jellyfin:", "live:one", "recording:not-a-uuid", "series:12", "film:500"] {
            #expect(TopShelfLink.Item(id: id) == nil, "\(id)")
        }
    }

    @Test func idsRoundTrip() {
        let items: [TopShelfLink.Item] = [.movie(500), .episode(series: 800, episode: "7041"), .jellyfin("a1b2c3"), .live(101), .recording(UUID())]
        for item in items { #expect(TopShelfLink.Item(id: item.id) == item) }
    }

    @Test func parsesPlayAndOpenURLs() {
        #expect(TopShelfLink(url: URL(string: "fernsy://play?item=live:101")!) == TopShelfLink(.play, .live(101)))
        #expect(TopShelfLink(url: URL(string: "fernsy://open?item=movie:500")!) == TopShelfLink(.open, .movie(500)))
        #expect(TopShelfLink(url: URL(string: "FERNSY://PLAY?item=movie%3A500")!) == TopShelfLink(.play, .movie(500)))
        #expect(TopShelfLink(url: URL(string: "fernsy://play?other=1&item=episode:800:7041")!) == TopShelfLink(.play, .episode(series: 800, episode: "7041")))
    }

    @Test func refusesOtherURLs() {
        for text in ["https://play?item=live:101", "fernsy://delete?item=live:101", "fernsy://play", "fernsy://play?item=",
                     "fernsy://play?item=live:x", "fernsy://?item=live:101"] {
            #expect(TopShelfLink(url: URL(string: text)!) == nil, "\(text)")
        }
    }

    @Test func urlsRoundTrip() {
        let links = [TopShelfLink(.play, .movie(500)), TopShelfLink(.open, .jellyfin("a1b2c3")), TopShelfLink(.play, .episode(series: 800, episode: "7041")),
                     TopShelfLink(.play, .recording(UUID()))]
        for link in links { #expect(TopShelfLink(url: link.url) == link) }
        #expect(TopShelfLink(.play, .live(101)).url.absoluteString == "fernsy://play?item=live:101")
    }

    @Test func onlyFilmsEpisodesAndJellyfinHavePages() {
        #expect(TopShelfLink.Item.movie(1).hasPage)
        #expect(TopShelfLink.Item.episode(series: 1, episode: "2").hasPage)
        #expect(TopShelfLink.Item.jellyfin("x").hasPage)
        #expect(!TopShelfLink.Item.live(1).hasPage)
        #expect(!TopShelfLink.Item.recording(UUID()).hasPage)
    }

    // MARK: Snapshot

    private func item(_ n: Int, image: String? = nil) -> TopShelfSnapshot.Item {
        let link = TopShelfLink.Item.movie(n)
        return TopShelfSnapshot.Item(id: link.id, title: "Film \(n)", subtitle: "\(n) min left", image: image, progress: 0.5,
                                     play: TopShelfLink(.play, link).url, display: TopShelfLink(.open, link).url)
    }

    @Test func rowsKeepAtMostTenItems() {
        let snapshot = TopShelfSnapshot(sections: [.init(kind: .continueWatching, shape: .hdtv, items: (1...14).map { item($0) })])
        #expect(TopShelfSnapshot.maxItems == 10)
        #expect(snapshot.sections[0].items.map(\.id) == (1...10).map { "movie:\($0)" })
    }

    @Test func emptyRowsAreLeftOut() {
        let snapshot = TopShelfSnapshot(sections: [.init(kind: .continueWatching, shape: .hdtv, items: []),
                                                   .init(kind: .favoriteChannels, shape: .square, items: [item(1)]),
                                                   .init(kind: .recordings, shape: .hdtv, items: [])])
        #expect(snapshot.sections.map(\.kind) == [.favoriteChannels])
        #expect(TopShelfSnapshot(sections: []).isEmpty)
    }

    @Test func encodesAndDecodes() throws {
        let snapshot = TopShelfSnapshot(sections: [.init(kind: .continueWatching, shape: .hdtv, items: [item(1, image: "a.jpg"), item(2)]),
                                                   .init(kind: .recentChannels, shape: .square, items: [item(3, image: "b.jpg")])])
        let data = try TopShelfSnapshot.encode(snapshot)
        #expect(try TopShelfSnapshot.decode(data) == snapshot)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let first = try #require((json["sections"] as? [[String: Any]])?.first)
        #expect(first["kind"] as? String == "continueWatching")
        #expect(first["shape"] as? String == "hdtv")
        let tile = try #require((first["items"] as? [[String: Any]])?.first)
        #expect(tile["play"] as? String == "fernsy://play?item=movie:1")
        #expect(tile["display"] as? String == "fernsy://open?item=movie:1")
        #expect(tile["image"] as? String == "a.jpg")
        #expect(snapshot.imageNames == ["a.jpg", "b.jpg"])
    }

    @Test func decodingAppliesTheLimit() throws {
        let long = TopShelfSnapshot.Section(kind: .recordings, shape: .hdtv, items: (1...12).map { item($0) })
        let data = try JSONEncoder().encode(["sections": [long]])
        #expect(try TopShelfSnapshot.decode(data).sections[0].items.count == 10)
    }

    @Test func appGroupComesFromTheAppsBundleId() {
        #expect(TopShelfSnapshot.appGroup(bundleIdentifier: "de.mobilistics.fernsy") == "group.de.mobilistics.fernsy")
        #expect(TopShelfSnapshot.appGroup(bundleIdentifier: "de.mobilistics.fernsy.topshelf") == "group.de.mobilistics.fernsy")
        #expect(TopShelfSnapshot.appGroup(bundleIdentifier: "de.mobilistics.fernsy.dev.topshelf") == "group.de.mobilistics.fernsy.dev")
    }
}
