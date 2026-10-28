import Foundation
import Testing
@testable import FernsyCore

/// Jellyfin answers (Fixtures/jellyfin, recorded from a local Docker test server with Jellyfin
/// 12.3.0; ids, tokens, addresses and online metadata replaced) decoded into the models.
struct JellyfinModelsTests {
    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/jellyfin"))
        return try JellyfinJSON.decoder.decode(T.self, from: try Data(contentsOf: url))
    }

    @Test func publicInfoAndSignIn() throws {
        let info = try Self.decode(JFPublicInfo.self, "public_info")
        #expect(info.version == "12.3.0")
        #expect(info.id?.count == 32)
        let auth = try Self.decode(JFAuthResult.self, "authenticate")
        #expect(auth.user.name == "fixture")
        #expect(auth.accessToken.allSatisfy { $0 == "0" || $0.isHexDigit })
    }

    @Test func libraryViews() throws {
        let views = try Self.decode(JFItemsPage.self, "views").items
        #expect(Set(views.compactMap(\.collectionType)) == ["movies", "tvshows"])
    }

    @Test func moviePageAndDetails() throws {
        let page = try Self.decode(JFItemsPage.self, "items")
        let movie = try #require(page.items.first)
        #expect(movie.type == "Movie")
        #expect(movie.productionYear == 2020)
        #expect(!movie.isFolder)
        let detail = try Self.decode(JFItem.self, "item")
        let source = try #require(detail.mediaSources?.first)
        #expect(source.container == "mkv")
        let streams = source.mediaStreams ?? []
        #expect(streams.contains { $0.type == "Video" && $0.codec == "h264" })
        #expect(streams.contains { $0.type == "Audio" && $0.codec == "aac" })
    }

    @Test func seasonsAndEpisodes() throws {
        let seasons = try Self.decode(JFItemsPage.self, "seasons").items
        #expect(seasons.first?.type == "Season")
        #expect(seasons.first?.isFolder == true)
        let episode = try #require(try Self.decode(JFItemsPage.self, "episodes").items.first)
        #expect(episode.type == "Episode")
        #expect(episode.seriesName == "Test Show")
        #expect(episode.indexNumber == 1)
        #expect(episode.parentIndexNumber == 1)
    }

    @Test func playbackInfoAndPlayedMark() throws {
        let info = try Self.decode(JFPlaybackInfo.self, "playback_info")
        #expect(!info.mediaSources.isEmpty)
        let data = try Self.decode(JFUserData.self, "user_data")
        #expect(data.played == true)
    }

    /// No fixture carries anything from a real server.
    /// One URL per backdrop (`Images/Backdrop/<index>`), at most five; episodes use the series'
    /// (tvos-living-hero).
    @Test func backdropURLsPerIndex() throws {
        func item(_ json: String) throws -> JFItem { try JSONDecoder().decode(JFItem.self, from: Data(json.utf8)) }
        let client = JellyfinClient(base: URL(string: "http://jf.test")!, token: nil)
        let film = try item(#"{"id":"f","name":"F","type":"Movie","backdropImageTags":["t0","t1","t2","t3","t4","t5"]}"#)
        let urls = client.backdropURLs(film, maxHeight: 1080)
        #expect(urls.count == 5)
        #expect(urls[0].hasPrefix("http://jf.test/Items/f/Images/Backdrop/0?tag=t0"))
        #expect(urls[1].hasPrefix("http://jf.test/Items/f/Images/Backdrop/1?tag=t1"))
        let single = try item(#"{"id":"g","name":"G","type":"Movie","backdropImageTags":["only"]}"#)
        #expect(client.backdropURLs(single, maxHeight: 1080).count == 1)
        let episode = try item(#"{"id":"e","name":"E","type":"Episode","backdropImageTags":[],"parentBackdropItemId":"s","parentBackdropImageTags":["p0","p1"]}"#)
        #expect(client.backdropURLs(episode, maxHeight: 1080).map { $0.contains("/Items/s/Images/Backdrop/") } == [true, true])
        #expect(client.backdropURLs(try item(#"{"id":"n","name":"N","type":"Movie"}"#), maxHeight: 1080).isEmpty)
    }

    @Test func fixturesAreAnonymous() throws {
        let folder = try #require(Bundle.module.url(forResource: "jellyfin", withExtension: nil, subdirectory: "Fixtures"))
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("192.168."), "\(file.lastPathComponent)")
            #expect(!text.contains("fixture-pass"), "\(file.lastPathComponent)")
        }
    }
}
