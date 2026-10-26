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
    @Test func fixturesAreAnonymous() throws {
        let folder = try #require(Bundle.module.url(forResource: "jellyfin", withExtension: nil, subdirectory: "Fixtures"))
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("192.168."), "\(file.lastPathComponent)")
            #expect(!text.contains("fixture-pass"), "\(file.lastPathComponent)")
        }
    }
}
