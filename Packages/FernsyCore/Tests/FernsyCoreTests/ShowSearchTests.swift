import Foundation
import Testing
@testable import FernsyCore

/// Shows of the favourite channels in the Mac's toolbar search (search-favorite-shows).
struct ShowSearchTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func channel(_ id: Int) -> LiveChannel {
        let json = #"{"stream_id":\#(id),"name":"Channel \#(id)","category_id":"1"}"#
        return try! JSONDecoder().decode(LiveChannel.self, from: Data(json.utf8))
    }

    private func show(_ title: String, from minutes: Double, to end: Double) -> EPGEntry {
        EPGEntry(id: "\(title)\(minutes)", title: title, description: "Krimi aus Münster", start: now + minutes * 60, end: now + end * 60)
    }

    @Test func matchesTitlesIgnoringCaseAndDiacritics() {
        let search = ShowSearch(channels: [channel(1)], guides: [1: [show("Tatort: Münster", from: 60, to: 150), show("Tagesschau", from: 0, to: 15)]])
        #expect(search.search(makeSearchKey("MUNSTER"), now: now).map(\.entry.title) == ["Tatort: Münster"])
        // Descriptions do not count.
        #expect(search.search(makeSearchKey("krimi"), now: now).isEmpty)
    }

    @Test func runningFirstThenByStart() {
        let search = ShowSearch(channels: [channel(1), channel(2)], guides: [
            1: [show("Tatort", from: 120, to: 210), show("Tatort", from: 30, to: 120)],
            2: [show("Tatort", from: -20, to: 70)],
        ])
        let hits = search.search("tatort", now: now)
        #expect(hits.map(\.channel.id) == [2, 1, 1])
        #expect(hits.map(\.entry.start) == [now - 1200, now + 1800, now + 7200])
    }

    @Test func endedShowsAreLeftOut() {
        let search = ShowSearch(channels: [channel(1)], guides: [1: [show("Tatort", from: -120, to: -30), show("Tatort", from: -30, to: 0)]])
        #expect(search.search("tatort", now: now).isEmpty)
    }

    @Test func onlyTheFirstFiftyChannels() {
        let channels = (1...60).map(channel)
        let guides = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, [show("Tatort", from: 10, to: 100)]) })
        let hits = ShowSearch(channels: channels, guides: guides).search("tatort", now: now)
        #expect(hits.count == ShowSearch.channelLimit)
        #expect(Set(hits.map(\.channel.id)) == Set(1...50))
    }

    @Test func channelsWithoutGuideOrQueryGiveNothing() {
        let search = ShowSearch(channels: [channel(1), channel(2)], guides: [1: []])
        #expect(search.search("tatort", now: now).isEmpty)
        #expect(ShowSearch(channels: [channel(1)], guides: [1: [show("Tatort", from: 0, to: 90)]]).search("", now: now).isEmpty)
    }
}
