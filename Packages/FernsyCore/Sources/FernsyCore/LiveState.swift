import Foundation

/// Live categories and channels the user has hidden, for one provider account.
///
/// One small self-contained value (provider ids only, with `modifiedAt`), so a later sync can
/// store it as a single entry per account and merge by set union or last writer. Ids that are
/// missing from the current catalog are kept: the provider may bring them back, and another
/// device may know them.
public struct ChannelVisibility: Codable, Equatable, Sendable {
    public var version = 1
    public var hiddenCategories: Set<String> = []
    public var hiddenChannels: Set<Int> = []
    public var modifiedAt = Date(timeIntervalSince1970: 0)

    public static let fileName = "visibility.json"

    public init() {}

    /// Hidden itself or through its category: channels of a hidden category are hidden everywhere.
    public func isHidden(_ channel: LiveChannel) -> Bool {
        hiddenChannels.contains(channel.id) || hiddenCategories.contains(channel.categoryId ?? "")
    }

    /// The stored value in an account folder; empty if there is none or it is unreadable.
    public static func load(from dir: URL) -> ChannelVisibility {
        AccountFile.load(fileName, from: dir) ?? ChannelVisibility()
    }

    public func save(to dir: URL) {
        AccountFile.save(self, as: Self.fileName, to: dir)
    }
}

/// Live categories the user pinned into the category column (Apple TV), in pinning order, for
/// one provider account. Same shape and rules as `ChannelVisibility`.
public struct PinnedCategories: Codable, Equatable, Sendable {
    public var version = 1
    public var categories: [String] = []
    public var modifiedAt = Date(timeIntervalSince1970: 0)

    public static let fileName = "pinned.json"

    public init() {}

    public func contains(_ id: String) -> Bool { categories.contains(id) }

    /// Pins at the end, or unpins.
    public mutating func set(_ id: String, pinned: Bool) {
        categories.removeAll { $0 == id }
        if pinned { categories.append(id) }
        modifiedAt = Date()
    }

    public static func load(from dir: URL) -> PinnedCategories {
        AccountFile.load(fileName, from: dir) ?? PinnedCategories()
    }

    public func save(to dir: URL) {
        AccountFile.save(self, as: Self.fileName, to: dir)
    }
}

/// Small JSON files in an account folder (ISO dates, sorted keys).
enum AccountFile {
    static func load<T: Decodable>(_ name: String, from dir: URL) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, as name: String, to dir: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }
}

/// Rules of the live lists shared by the Mac and the Apple TV app: stored keys, recently
/// watched channels, adult detection and the zap order.
public enum LiveRules {
    /// UserDefaults key of the favourites ("live:<id>", "movie:<id>", "series:<id>").
    public static let favoritesKey = "library.favorites"
    /// UserDefaults key of the recently watched channel ids, newest first.
    public static let recentKey = "live.recent"
    /// How many channels "Zuletzt gesehen" keeps.
    public static let recentLimit = 20

    /// The favourites key of a live channel.
    public static func favoriteKey(channel id: Int) -> String { "live:\(id)" }

    /// `list` with `channelId` played now: first, without duplicates, at most `recentLimit`.
    public static func noting(_ channelId: Int, in list: [Int]) -> [Int] {
        Array(([channelId] + list.filter { $0 != channelId }).prefix(recentLimit))
    }

    private static let adultMarkers = ["xxx", "adult", "+18", "18+", "for adults", "erotik"]

    /// A category whose name marks it as adult content.
    public static func isAdultCategory(_ category: XCategory) -> Bool {
        let name = category.name.lowercased()
        return adultMarkers.contains { name.contains($0) }
    }

    /// Channels the player zaps through, hidden ones included: the category the channel was
    /// started from, or everything if that category has no visible channel.
    public static func zapOrder(category: [LiveChannel]?, all: [LiveChannel], isHidden: (LiveChannel) -> Bool) -> [LiveChannel] {
        let list = category ?? []
        return list.contains { !isHidden($0) } ? list : all
    }

    /// The visible channel `offset` steps away from `channelId` in `order` (wrapping), with its
    /// 1-based number. From a hidden channel it steps to the visible ones around its place.
    public static func neighbor(of channelId: Int, in order: [LiveChannel], offset: Int,
                                isHidden: (LiveChannel) -> Bool) -> (channel: LiveChannel, number: Int)? {
        let list = order.filter { !isHidden($0) }
        guard !list.isEmpty else { return nil }
        let index: Int
        if let current = list.firstIndex(where: { $0.id == channelId }) {
            index = current + offset
        } else {
            guard offset != 0, let position = order.firstIndex(where: { $0.id == channelId }) else { return nil }
            // Visible channels before the hidden one: the next one down has this index.
            let before = order[..<position].filter { !isHidden($0) }.count
            index = offset > 0 ? before + offset - 1 : before + offset
        }
        let next = (index % list.count + list.count) % list.count
        return (list[next], next + 1)
    }
}
