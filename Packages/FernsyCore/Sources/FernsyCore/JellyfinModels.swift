import Foundation

/// A signed-in Jellyfin user on one server. Kept in the keychain; never holds the password.
public struct JFSession: Codable, Equatable, Sendable {
    public var server: String
    public var serverId: String
    public var serverName: String
    public var version: String
    public var userId: String
    public var userName: String
    public var token: String

    public var baseURL: URL? { JFSession.normalize(server) }

    /// Cache folder name: one per server and user.
    public var cacheKey: String { "jellyfin-\(serverId)-\(userId)" }

    public static func normalize(_ server: String) -> URL? {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    public init(server: String, serverId: String, serverName: String, version: String, userId: String, userName: String, token: String) {
        self.server = server
        self.serverId = serverId
        self.serverName = serverName
        self.version = version
        self.userId = userId
        self.userName = userName
        self.token = token
    }
}

public struct JFPublicInfo: Decodable, Sendable {
    public let productName: String?
    public let serverName: String?
    public let version: String?
    public let id: String?
}

public struct JFAuthResult: Decodable, Sendable {
    public struct User: Decodable, Sendable {
        public let id: String
        public let name: String
    }
    public let accessToken: String
    public let user: User
}

public struct JFUserData: Codable, Hashable, Sendable {
    public var played: Bool?
    public var playedPercentage: Double?
    public var unplayedItemCount: Int?
    public var isFavorite: Bool?
    public var playbackPositionTicks: Int64?
    public var playCount: Int?
    public var lastPlayedDate: String?

    public init(played: Bool? = nil, playedPercentage: Double? = nil, unplayedItemCount: Int? = nil, isFavorite: Bool? = nil, playbackPositionTicks: Int64? = nil, playCount: Int? = nil, lastPlayedDate: String? = nil) {
        self.played = played
        self.playedPercentage = playedPercentage
        self.unplayedItemCount = unplayedItemCount
        self.isFavorite = isFavorite
        self.playbackPositionTicks = playbackPositionTicks
        self.playCount = playCount
        self.lastPlayedDate = lastPlayedDate
    }
}

public struct JFPerson: Codable, Hashable, Sendable {
    public let name: String
    public let role: String?
    public let type: String?
}

public struct JFMediaStream: Codable, Hashable, Sendable {
    public let type: String?
    public let codec: String?
    public let language: String?
    public let displayTitle: String?
    public let isExternal: Bool?
    public var index: Int?
    public var videoRangeType: String?
    public var isTextSubtitleStream: Bool?
    public var isDefault: Bool?
    public var isForced: Bool?
    public var title: String?

    /// The stream as a player track with Fernsy's id for it.
    public func track(id: Int32, suffix: String = "") -> MediaTrack {
        MediaTrack(id: id, title: (displayTitle ?? language ?? "") + suffix, language: MediaNames.languageCode(language),
                   isForced: isForced == true || MediaNames.titleSaysForced(title) || MediaNames.titleSaysForced(displayTitle),
                   isDefault: isDefault == true)
    }
}

public struct JFMediaSource: Codable, Hashable, Sendable {
    public let id: String?
    public let name: String?
    public let container: String?
    public let mediaStreams: [JFMediaStream]?
    public var runTimeTicks: Int64?
    public var transcodingUrl: String?
}

public struct JFPlaybackInfo: Decodable, Sendable {
    public let mediaSources: [JFMediaSource]
    public let playSessionId: String?
}

/// Films, series, seasons and episodes as Jellyfin returns them (only the fields we ask for).
public struct JFItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let type: String
    public var sortName: String?
    public var productionYear: Int?
    public var premiereDate: String?
    public var dateCreated: String?
    public var communityRating: Double?
    public var officialRating: String?
    public var genres: [String]?
    public var runTimeTicks: Int64?
    public var overview: String?
    public var imageTags: [String: String]?
    public var backdropImageTags: [String]?
    public var parentBackdropItemId: String?
    public var parentBackdropImageTags: [String]?
    public var parentThumbItemId: String?
    public var parentThumbImageTag: String?
    public var seriesId: String?
    public var seriesName: String?
    public var seriesPrimaryImageTag: String?
    public var seasonId: String?
    public var indexNumber: Int?
    public var parentIndexNumber: Int?
    public var childCount: Int?
    public var recursiveItemCount: Int?
    public var collectionType: String?
    public var people: [JFPerson]?
    public var mediaSources: [JFMediaSource]?
    public var userData: JFUserData?

    public var isSeries: Bool { type == "Series" }
    public var isFolder: Bool { type == "Series" || type == "Season" }
    public var isPlayed: Bool { userData?.played ?? false }
    public var isFavorite: Bool { userData?.isFavorite ?? false }

    /// 0…1 when partly watched.
    public var progress: Double? {
        guard let position = userData?.playbackPositionTicks, position > 0, let total = runTimeTicks, total > 0 else { return nil }
        return min(1, Double(position) / Double(total))
    }

    public var runtimeMinutes: Int? { runTimeTicks.map { Int($0 / 600_000_000) } }

    public var year: Int? {
        productionYear ?? premiereDate.flatMap { Int($0.prefix(4)) }
    }

    /// Sort keys: Jellyfin writes every date as UTC ISO 8601 in the same format, so the strings
    /// sort chronologically. Parsing them in a sort comparator stalled scrolling.
    public var addedKey: String { dateCreated ?? "" }
    public var releaseKey: String { premiereDate ?? "" }
}

public struct JFItemsPage: Decodable, Sendable {
    public let items: [JFItem]
    public let totalRecordCount: Int?
}

public enum JellyfinError: LocalizedError, Equatable, Sendable {
    case notJellyfin
    case unauthorized
    case wrongCredentials
    case http(Int)
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .notJellyfin: return String(localized: "No Jellyfin server was found at this address.", bundle: .module)
        case .unauthorized: return String(localized: "The Jellyfin session has expired.", bundle: .module)
        case .wrongCredentials: return String(localized: "Username or password is wrong.", bundle: .module)
        case .http(let code): return String(localized: "The Jellyfin server answers with HTTP \(code).", bundle: .module)
        case .invalidURL: return String(localized: "The server address is not valid.", bundle: .module)
        }
    }
}
