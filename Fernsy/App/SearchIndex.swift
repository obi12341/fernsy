import Foundation

/// The sources the toolbar search covers, in the order the results show them.
enum SearchSource: Int, CaseIterable, Sendable {
    case channels, movies, series, recordings, jellyfinFilms, jellyfinSeries
}

/// One searchable name: `index` points into that source's list, `key` is the name folded with
/// `makeSearchKey` (case and diacritics ignored).
struct SearchEntry: Sendable {
    let source: SearchSource
    let index: Int
    let key: String
}

/// All searchable names of all sources in one flat list. Built off the main thread whenever a
/// source changes; a query only compares strings (about 20 ms for 50,000 entries).
struct SearchIndex: Sendable {
    let entries: [SearchEntry]

    /// Indices per source, best hits first: the name starts with the query, then a word in it
    /// starts with the query, then it contains it anywhere; alphabetical within each rank.
    /// `needle` must already be folded with `makeSearchKey`.
    func search(_ needle: String) -> [SearchSource: [Int]] {
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
}

private extension Character {
    var isLetterOrDigit: Bool { isLetter || isNumber }
}
