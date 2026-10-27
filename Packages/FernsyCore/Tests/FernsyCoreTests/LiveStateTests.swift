import Foundation
import Testing
@testable import FernsyCore

/// Live list rules shared by the Mac and the Apple TV app (channel-visibility, live-tv specs):
/// hiding, recently watched, adult detection, zap order, and the stored files.
struct LiveStateTests {
    static func channel(_ id: Int, category: String) -> LiveChannel {
        let json = #"{"stream_id": \#(id), "name": "Kanal \#(id)", "category_id": "\#(category)"}"#
        return try! JSONDecoder().decode(LiveChannel.self, from: Data(json.utf8))
    }

    static let news = (1...4).map { channel($0, category: "news") }
    static let sport = (5...6).map { channel($0, category: "sport") }

    @Test func hiddenCategoryHidesItsChannels() {
        var visibility = ChannelVisibility()
        visibility.hiddenCategories = ["sport"]
        visibility.hiddenChannels = [2]
        #expect(visibility.isHidden(Self.sport[0]))
        #expect(visibility.isHidden(Self.news[1]))
        #expect(!visibility.isHidden(Self.news[0]))
    }

    @Test func recentlyWatchedIsNewestFirstWithoutDuplicates() {
        var list: [Int] = []
        for id in [7, 3, 7, 9] { list = LiveRules.noting(id, in: list) }
        #expect(list == [9, 7, 3])
        for id in 100..<130 { list = LiveRules.noting(id, in: list) }
        #expect(list.count == LiveRules.recentLimit)
        #expect(list.first == 129)
    }

    @Test func adultCategoriesByName() {
        #expect(LiveRules.isAdultCategory(XCategory(id: "1", name: "XXX | Night")))
        #expect(LiveRules.isAdultCategory(XCategory(id: "2", name: "DE: Erotik 18+")))
        #expect(!LiveRules.isAdultCategory(XCategory(id: "3", name: "DE: Nachrichten")))
    }

    @Test func zapSkipsHiddenAndWraps() {
        let hidden: Set<Int> = [2]
        let isHidden = { (c: LiveChannel) in hidden.contains(c.id) }
        let order = LiveRules.zapOrder(category: Self.news, all: Self.news + Self.sport, isHidden: isHidden)
        #expect(LiveRules.neighbor(of: 1, in: order, offset: 1, isHidden: isHidden)?.channel.id == 3)
        #expect(LiveRules.neighbor(of: 4, in: order, offset: 1, isHidden: isHidden)?.channel.id == 1)
        #expect(LiveRules.neighbor(of: 1, in: order, offset: -1, isHidden: isHidden)?.number == 3)
        // From the hidden channel 2: down is 3, up is 1.
        #expect(LiveRules.neighbor(of: 2, in: order, offset: 1, isHidden: isHidden)?.channel.id == 3)
        #expect(LiveRules.neighbor(of: 2, in: order, offset: -1, isHidden: isHidden)?.channel.id == 1)
    }

    @Test func zapFallsBackToAllWhenTheCategoryIsHidden() {
        let isHidden = { (c: LiveChannel) in c.categoryId == "sport" }
        let order = LiveRules.zapOrder(category: Self.sport, all: Self.news + Self.sport, isHidden: isHidden)
        #expect(order.count == 6)
    }

    @Test func pinnedCategoriesKeepOrderAndRoundTrip() throws {
        var pinned = PinnedCategories()
        pinned.set("sport", pinned: true)
        pinned.set("news", pinned: true)
        pinned.set("sport", pinned: true)
        #expect(pinned.categories == ["news", "sport"])
        pinned.set("news", pinned: false)
        #expect(pinned.categories == ["sport"])

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        pinned.save(to: dir)
        #expect(PinnedCategories.load(from: dir).categories == ["sport"])
        var visibility = ChannelVisibility()
        visibility.hiddenChannels = [5]
        visibility.save(to: dir)
        #expect(ChannelVisibility.load(from: dir).hiddenChannels == [5])
    }

    @Test func valuesRoundTripAsData() {
        var pinned = PinnedCategories()
        pinned.set("7", pinned: true)
        #expect(PinnedCategories.decoded(pinned.encoded).categories == ["7"])
        #expect(ChannelVisibility.decoded(nil) == ChannelVisibility())
        #expect(ChannelVisibility.decoded(Data("garbage".utf8)) == ChannelVisibility())
    }

    /// The Mac's stored visibility.json from before the move still loads.
    @Test func existingVisibilityFileLoads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let stored = #"{"hiddenCategories":["12"],"hiddenChannels":[101],"modifiedAt":"2026-10-20T10:00:00Z","version":1}"#
        try Data(stored.utf8).write(to: dir.appendingPathComponent("visibility.json"))
        let value = ChannelVisibility.load(from: dir)
        #expect(value.hiddenCategories == ["12"])
        #expect(value.hiddenChannels == [101])
    }
}
