import Foundation

/// The Jellyfin overview's discovery rows (tvos-jellyfin-overview): built from the library the
/// apps already hold, without server requests, once per library change.
public struct JellyfinOverview: Sendable {
    /// A genre or decade to browse, with its titles and the artwork for its tile.
    public struct Tile: Identifiable, Sendable {
        public enum Kind: Hashable, Sendable { case genre(String), decade(Int) }
        public let kind: Kind
        public let items: [JFItem]
        public let artwork: JFItem?
        public var id: String {
            switch kind {
            case .genre(let name): "genre." + name
            case .decade(let year): "decade.\(year)"
            }
        }
    }

    /// The thresholds, in one place to tune them after trying the page.
    public enum Rules {
        public static let spotlightRating = 7.0
        public static let spotlightPool = 30
        public static let topRating = 7.5
        public static let shortMinutes = 100
        public static let shortRating = 6.5
        public static let almostDoneLeft = 1...3
        public static let rediscoverRating = 7.0
        public static let rediscoverAfter: TimeInterval = 365 * 86_400
        public static let tileMinimum = 3
        public static let rowLength = 20
    }

    public var spotlightCandidates: [JFItem] = []
    public var favorites: [JFItem] = []
    public var topRated: [JFItem] = []
    public var almostDone: [JFItem] = []
    public var shortAndGood: [JFItem] = []
    public var rediscover: [JFItem] = []
    public var genres: [Tile] = []
    public var decades: [Tile] = []
    public var filmCount = 0
    public var seriesCount = 0
    /// Hours of unwatched films and episodes; nil when no runtime is known.
    public var unwatchedHours: Int?

    public init() {}

    public static func build(films: [JFItem], series: [JFItem], now: Date = Date()) -> JellyfinOverview {
        var overview = JellyfinOverview()
        let all = films + series
        let byRating: (JFItem, JFItem) -> Bool = { ($0.communityRating ?? 0) > ($1.communityRating ?? 0) }
        let unwatchedFilms = films.filter { !$0.isPlayed }

        // Well rated with a backdrop first; without ratings or backdrops on the server, the next
        // best, so the page still opens with a suggestion.
        let withBackdrop = unwatchedFilms.filter { !($0.backdropImageTags ?? []).isEmpty }
        let isRated: (JFItem) -> Bool = { ($0.communityRating ?? 0) >= Rules.spotlightRating }
        let newest: (JFItem, JFItem) -> Bool = { $0.addedKey > $1.addedKey }
        let pools = [withBackdrop.filter(isRated).sorted(by: byRating), withBackdrop.sorted(by: newest),
                     unwatchedFilms.filter(isRated).sorted(by: byRating), unwatchedFilms.sorted(by: newest)]
        overview.spotlightCandidates = Array((pools.first { !$0.isEmpty } ?? []).prefix(Rules.spotlightPool))

        overview.favorites = Array(all.filter(\.isFavorite).sorted { $0.addedKey > $1.addedKey }.prefix(Rules.rowLength))
        overview.topRated = Array(all.filter { ($0.communityRating ?? 0) >= Rules.topRating && (($0.isSeries && !isStarted($0)) || (!$0.isSeries && !$0.isPlayed)) }
            .sorted(by: byRating).prefix(Rules.rowLength))
        overview.almostDone = Array(series.filter { item in
            guard let left = episodesLeft(item), isStarted(item) else { return false }
            return Rules.almostDoneLeft.contains(left)
        }.sorted { (episodesLeft($0) ?? 0, $1.userData?.lastPlayedDate ?? "") < (episodesLeft($1) ?? 0, $0.userData?.lastPlayedDate ?? "") }
            .prefix(Rules.rowLength))
        overview.shortAndGood = Array(unwatchedFilms.filter { item in
            guard let minutes = item.runtimeMinutes, minutes > 0 else { return false }
            return minutes < Rules.shortMinutes && (item.communityRating ?? 0) >= Rules.shortRating
        }.sorted(by: byRating).prefix(Rules.rowLength))
        overview.rediscover = Array(all.filter { item in
            guard isFinished(item), (item.communityRating ?? 0) >= Rules.rediscoverRating,
                  let last = lastPlayed(item) else { return false }
            return now.timeIntervalSince(last) > Rules.rediscoverAfter
        }.sorted { (lastPlayed($0) ?? .distantPast) < (lastPlayed($1) ?? .distantPast) }.prefix(Rules.rowLength))

        var byGenre: [String: [JFItem]] = [:]
        for item in all { for genre in Set(item.genres ?? []) { byGenre[genre, default: []].append(item) } }
        overview.genres = byGenre.filter { $0.value.count >= Rules.tileMinimum }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .map { tile(.genre($0.key), $0.value, byRating) }
        let byDecade = Dictionary(grouping: all.filter { $0.year != nil }) { ($0.year! / 10) * 10 }
        overview.decades = byDecade.filter { $0.value.count >= Rules.tileMinimum }
            .sorted { $0.key > $1.key }
            .map { tile(.decade($0.key), $0.value, byRating) }

        overview.filmCount = films.count
        overview.seriesCount = series.count
        var minutes = 0
        var known = false
        for film in unwatchedFilms { if let m = film.runtimeMinutes { minutes += m; known = true } }
        for show in series {
            // A series' runtime is its typical episode length.
            if let m = show.runtimeMinutes, let left = episodesLeft(show) { minutes += m * left; known = true }
        }
        overview.unwatchedHours = known ? minutes / 60 : nil
        return overview
    }

    /// Another spotlight film, not one of the `recent` ids when others are left.
    public static func pick(from candidates: [JFItem], avoiding recent: [String]) -> JFItem? {
        let fresh = candidates.filter { !recent.contains($0.id) }
        return (fresh.isEmpty ? candidates : fresh).randomElement()
    }

    /// Episodes not watched yet, from the series' counts.
    public static func episodesLeft(_ series: JFItem) -> Int? {
        series.userData?.unplayedItemCount
    }

    private static func isStarted(_ series: JFItem) -> Bool {
        guard let left = series.userData?.unplayedItemCount, let total = series.recursiveItemCount else { return series.isPlayed }
        return left < total
    }

    private static func isFinished(_ item: JFItem) -> Bool {
        item.isSeries ? (item.userData?.unplayedItemCount == 0 && isStarted(item)) || item.isPlayed : item.isPlayed
    }

    /// Jellyfin writes seven fraction digits ("2024-05-01T20:15:00.0000000Z"); the seconds are enough.
    static func lastPlayed(_ item: JFItem) -> Date? {
        guard let text = item.userData?.lastPlayedDate, text.count >= 19 else { return nil }
        return try? Date(String(text.prefix(19)) + "Z", strategy: .iso8601)
    }

    private static func tile(_ kind: Tile.Kind, _ items: [JFItem], _ byRating: (JFItem, JFItem) -> Bool) -> Tile {
        let sorted = items.sorted(by: byRating)
        return Tile(kind: kind, items: sorted, artwork: sorted.first { !($0.backdropImageTags ?? []).isEmpty } ?? sorted.first)
    }
}
