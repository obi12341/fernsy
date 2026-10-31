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
}
