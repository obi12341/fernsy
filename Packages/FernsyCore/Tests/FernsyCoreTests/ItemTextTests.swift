import Foundation
import Testing
@testable import FernsyCore

/// Item helpers shared by the apps (code-structure-cleanup 3.3).
struct ItemTextTests {
    @Test func ticksConvert() {
        #expect(JellyfinTicks.seconds(12_000_000_000) == 1200)
        #expect(JellyfinTicks.ticks(1.5) == 15_000_000)
    }

    @Test func jellyfinItemSeconds() throws {
        let item = try JSONDecoder().decode(JFItem.self, from: Data(#"{"id":"a","name":"A","type":"Movie","runTimeTicks":72000000000,"userData":{"playbackPositionTicks":6000000000}}"#.utf8))
        #expect(item.runTimeSeconds == 7200)
        #expect(item.positionSeconds == 600)
        let fresh = try JSONDecoder().decode(JFItem.self, from: Data(#"{"id":"b","name":"B","type":"Movie"}"#.utf8))
        #expect(fresh.runTimeSeconds == nil)
        #expect(fresh.positionSeconds == 0)
    }

    @Test func channelAndTimeJoinsWithADot() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(ItemText.channelAndTime("Das Erste", date) == "Das Erste · " + ItemText.shortDateTime(date))
    }

    @Test func keys() {
        #expect(ResumeStore.cloudKey("x1") == "cloud.x1")
        #expect(ResumeStore.episodeKey("77") == "episode.77")
    }

    // MARK: episode-label-next-episode

    @Test func episodeCodePerLanguage() throws {
        #expect(String(localized: "S\(1) E\(2)", bundle: .fernsyCore, locale: Locale(identifier: "en")) == "S1 E2")
        let path = try #require(Bundle.fernsyCore.path(forResource: "de", ofType: "lproj"))
        let german = try #require(Bundle(path: path)).localizedString(forKey: "S%lld E%lld", value: nil, table: nil)
        #expect(String(format: german, 1, 2) == "S1 F2")
        #expect(String(format: german, 12, 104) == "S12 F104")
    }

    /// Two seasons: S1 with 4 episodes (listed out of order), S2 with 2.
    private static func series() throws -> SeriesInfo {
        func ep(_ id: Int, _ season: Int, _ number: Int) -> String {
            #"{"id":"\#(id)","episode_num":\#(number),"season":\#(season),"title":"E\#(id)"}"#
        }
        let json = #"{"episodes":{"1":[\#(ep(13, 1, 3)),\#(ep(11, 1, 1)),\#(ep(14, 1, 4)),\#(ep(12, 1, 2))],"2":[\#(ep(21, 2, 1)),\#(ep(22, 2, 2))]}}"#
        return try JSONDecoder().decode(SeriesInfo.self, from: Data(json.utf8))
    }

    private static func next(_ info: SeriesInfo, started: Set<String> = [], watched: Set<String> = []) -> String? {
        info.nextEpisode(position: { started.contains($0.id) ? 60 : 0 }, watched: { watched.contains($0.id) })?.id
    }

    @Test func nextEpisodeRule() throws {
        let info = try Self.series()
        #expect(Self.next(info) == "11", "nothing watched: the first")
        #expect(Self.next(info, started: ["13"], watched: ["11", "12", "14"]) == "13", "a started episode comes first")
        #expect(Self.next(info, watched: ["11", "13"]) == "14", "after the last watched, not the skipped one")
        #expect(Self.next(info, watched: ["11", "12", "13", "14"]) == "21", "across the season boundary")
        #expect(Self.next(info, watched: ["11", "12", "13", "14", "21", "22"]) == "22", "all watched: the last")
    }
}
