import Foundation

/// A signed-in Jellyfin user on one server. Kept in the keychain; never holds the password.
struct JFSession: Codable, Equatable {
    var server: String
    var serverId: String
    var serverName: String
    var version: String
    var userId: String
    var userName: String
    var token: String

    var baseURL: URL? { JFSession.normalize(server) }

    /// Cache folder name: one per server and user.
    var cacheKey: String { "jellyfin-\(serverId)-\(userId)" }

    static func normalize(_ server: String) -> URL? {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }
}

struct JFPublicInfo: Decodable {
    let productName: String?
    let serverName: String?
    let version: String?
    let id: String?
}

struct JFAuthResult: Decodable {
    struct User: Decodable {
        let id: String
        let name: String
    }
    let accessToken: String
    let user: User
}

struct JFUserData: Codable, Hashable {
    var played: Bool?
    var playedPercentage: Double?
    var unplayedItemCount: Int?
    var isFavorite: Bool?
    var playbackPositionTicks: Int64?
    var playCount: Int?
    var lastPlayedDate: String?
}

struct JFPerson: Codable, Hashable {
    let name: String
    let role: String?
    let type: String?
}

struct JFMediaStream: Codable, Hashable {
    let type: String?
    let codec: String?
    let language: String?
    let displayTitle: String?
    let isExternal: Bool?
    var index: Int?
    var videoRangeType: String?
    var isTextSubtitleStream: Bool?
    var isDefault: Bool?
    var isForced: Bool?
    var title: String?

    /// The stream as a player track with Fernsy's id for it.
    func track(id: Int32, suffix: String = "") -> MediaTrack {
        MediaTrack(id: id, title: (displayTitle ?? language ?? "") + suffix, language: MediaNames.languageCode(language),
                   isForced: isForced == true || MediaNames.titleSaysForced(title) || MediaNames.titleSaysForced(displayTitle),
                   isDefault: isDefault == true)
    }
}

struct JFMediaSource: Codable, Hashable {
    let id: String?
    let name: String?
    let container: String?
    let mediaStreams: [JFMediaStream]?
    var runTimeTicks: Int64?
    var transcodingUrl: String?
}

struct JFPlaybackInfo: Decodable {
    let mediaSources: [JFMediaSource]
    let playSessionId: String?
}

/// Films, series, seasons and episodes as Jellyfin returns them (only the fields we ask for).
struct JFItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    var sortName: String?
    var productionYear: Int?
    var premiereDate: String?
    var dateCreated: String?
    var communityRating: Double?
    var officialRating: String?
    var genres: [String]?
    var runTimeTicks: Int64?
    var overview: String?
    var imageTags: [String: String]?
    var backdropImageTags: [String]?
    var parentBackdropItemId: String?
    var parentBackdropImageTags: [String]?
    var parentThumbItemId: String?
    var parentThumbImageTag: String?
    var seriesId: String?
    var seriesName: String?
    var seriesPrimaryImageTag: String?
    var seasonId: String?
    var indexNumber: Int?
    var parentIndexNumber: Int?
    var childCount: Int?
    var recursiveItemCount: Int?
    var collectionType: String?
    var people: [JFPerson]?
    var mediaSources: [JFMediaSource]?
    var userData: JFUserData?

    var isSeries: Bool { type == "Series" }
    var isFolder: Bool { type == "Series" || type == "Season" }
    var isPlayed: Bool { userData?.played ?? false }
    var isFavorite: Bool { userData?.isFavorite ?? false }

    /// 0…1 when partly watched.
    var progress: Double? {
        guard let position = userData?.playbackPositionTicks, position > 0, let total = runTimeTicks, total > 0 else { return nil }
        return min(1, Double(position) / Double(total))
    }

    var runtimeMinutes: Int? { runTimeTicks.map { Int($0 / 600_000_000) } }

    var year: Int? {
        productionYear ?? premiereDate.flatMap { Int($0.prefix(4)) }
    }

    /// Sort keys: Jellyfin writes every date as UTC ISO 8601 in the same format, so the strings
    /// sort chronologically. Parsing them in a sort comparator stalled scrolling.
    var addedKey: String { dateCreated ?? "" }
    var releaseKey: String { premiereDate ?? "" }
}

struct JFItemsPage: Decodable {
    let items: [JFItem]
    let totalRecordCount: Int?
}

enum JellyfinError: LocalizedError, Equatable {
    case notJellyfin
    case unauthorized
    case wrongCredentials
    case http(Int)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .notJellyfin: return String(localized: "No Jellyfin server was found at this address.")
        case .unauthorized: return String(localized: "The Jellyfin session has expired.")
        case .wrongCredentials: return String(localized: "Username or password is wrong.")
        case .http(let code): return String(localized: "The Jellyfin server answers with HTTP \(code).")
        case .invalidURL: return String(localized: "The server address is not valid.")
        }
    }
}
