import Foundation

/// The sources the toolbar search covers, in the order the results show them.
public enum SearchSource: Int, CaseIterable, Sendable {
    case channels, movies, series, recordings, jellyfinFilms, jellyfinSeries
}

/// One searchable name: `index` points into that source's list, `key` is the name folded with
/// `makeSearchKey` (case and diacritics ignored).
public struct SearchEntry: Sendable {
    public let source: SearchSource
    public let index: Int
    public let key: String

    public init(source: SearchSource, index: Int, key: String) {
        self.source = source
        self.index = index
        self.key = key
    }
}

/// All searchable names of all sources in one flat list. Built off the main thread whenever a
/// source changes; a query only compares strings (about 20 ms for 50,000 entries).
public struct SearchIndex: Sendable {
    public let entries: [SearchEntry]

    /// Indices per source, best hits first: the name starts with the query, then a word in it
    /// starts with the query, then it contains it anywhere; alphabetical within each rank.
    /// `needle` must already be folded with `makeSearchKey`.
    public func search(_ needle: String) -> [SearchSource: [Int]] {
        guard !needle.isEmpty else { return [:] }
        var hits: [SearchSource: [(rank: UInt8, key: String, index: Int)]] = [:]
        for entry in entries {
            guard let range = entry.key.range(of: needle) else { continue }
            hits[entry.source, default: []].append((Self.rank(of: range, in: entry.key, needle: needle), entry.key, entry.index))
        }
        return hits.mapValues { list in
            list.sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.key < $1.key }.map(\.index)
        }
    }

    private static func rank(of first: Range<String.Index>, in key: String, needle: String) -> UInt8 {
        if first.lowerBound == key.startIndex { return 0 }
        var range = first
        while true {
            if !key[key.index(before: range.lowerBound)].isLetterOrDigit { return 1 }
            guard let next = key.range(of: needle, range: key.index(after: range.lowerBound)..<key.endIndex) else { return 2 }
            range = next
        }
    }

    public init(entries: [SearchEntry]) {
        self.entries = entries
    }
}

private extension Character {
    var isLetterOrDigit: Bool { isLetter || isNumber }
}

/// Live TV shows in the toolbar search (search-favorite-shows): the loaded guides of the
/// favourite channels, as folded titles, built when the guides or the favourites change. A query
/// only compares strings over a few thousand shows.
public struct ShowSearch: Sendable {
    /// The favourite channels searched, at most.
    public static let channelLimit = 50

    public struct Hit: Sendable {
        public let entry: EPGEntry
        public let channel: LiveChannel
    }

    private let shows: [(key: String, hit: Hit)]

    /// `channels` are the visible favourites in their order; `guides` the loaded entries per
    /// channel id (missing or empty when not loaded).
    public init(channels: [LiveChannel], guides: [Int: [EPGEntry]]) {
        var shows: [(key: String, hit: Hit)] = []
        for channel in channels.prefix(Self.channelLimit) {
            for entry in guides[channel.id] ?? [] {
                shows.append((makeSearchKey(entry.title), Hit(entry: entry, channel: channel)))
            }
        }
        self.shows = shows
    }

    /// Shows that run now or later whose title contains `needle` (folded with `makeSearchKey`):
    /// running ones first, then by start.
    public func search(_ needle: String, now: Date = Date()) -> [Hit] {
        guard !needle.isEmpty else { return [] }
        return shows.filter { $0.hit.entry.end > now && $0.key.contains(needle) }
            .map(\.hit)
            .sorted { a, b in
                let aRuns = a.entry.start <= now, bRuns = b.entry.start <= now
                return aRuns != bRuns ? aRuns : a.entry.start < b.entry.start
            }
    }
}
