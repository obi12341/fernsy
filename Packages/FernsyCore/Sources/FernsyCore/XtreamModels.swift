import Foundation

// Xtream Codes panels are loose with JSON types (ids as strings or ints, numbers
// as strings, null vs ""), so everything decodes leniently.
extension KeyedDecodingContainer {
    public func flexString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }

    public func flexInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) ?? Double(s).map { Int($0) } }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        return nil
    }

    public func flexDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }

    public func nonEmpty(_ key: Key) -> String? {
        guard let s = flexString(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// A list of strings that some panels send as a single string; empty entries dropped.
    public func stringList(_ key: Key) -> [String] {
        if let list = try? decode([String].self, forKey: key) {
            return list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return nonEmpty(key).map { [$0] } ?? []
    }
}

public func makeSearchKey(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
}

public struct XtreamCredentials: Codable, Equatable, Sendable {
    public var server: String
    public var username: String
    public var password: String

    public init(server: String, username: String, password: String) {
        self.server = server
        self.username = username
        self.password = password
    }

    public var baseURL: URL? {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    #if DEBUG
    /// IPTV_COPIEDACCOUNT: an account folder copied from the installed app, opened without its
    /// credentials (they stay in the installed app's keychain). The server never resolves.
    public static let copiedServer = "http://copied-account.invalid"
    public static var copied: XtreamCredentials? {
        guard let folder = ProcessInfo.processInfo.environment["IPTV_COPIEDACCOUNT"], !folder.isEmpty else { return nil }
        return XtreamCredentials(server: copiedServer, username: folder, password: "")
    }
    public var isCopied: Bool { server == Self.copiedServer }
    #endif

    /// Stable identifier for per-account cache folders.
    public var accountKey: String {
        #if DEBUG
        if isCopied { return username }
        #endif
        let raw = "\(server.lowercased())|\(username)"
        return String(raw.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" })
    }
}

public struct AccountInfo: Decodable, Sendable {
    public let auth: Bool
    public let status: String?
    public let expiresAt: Date?
    public let maxConnections: Int?
    public let activeConnections: Int?
    /// The server's time zone, in which archive (timeshift) requests name their start: its
    /// `timezone`, else derived from its `time_now`; nil without either (catch-up design 2).
    public let serverTimeZone: TimeZone?

    private enum Root: String, CodingKey { case user_info, server_info }
    private enum Keys: String, CodingKey { case auth, status, exp_date, max_connections, active_cons }
    private enum ServerKeys: String, CodingKey { case timezone, time_now }

    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: Root.self)
        let c = try root.nestedContainer(keyedBy: Keys.self, forKey: .user_info)
        auth = c.flexInt(.auth) == 1
        status = c.flexString(.status)
        expiresAt = c.flexInt(.exp_date).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        maxConnections = c.flexInt(.max_connections)
        activeConnections = c.flexInt(.active_cons)
        let server = try? root.nestedContainer(keyedBy: ServerKeys.self, forKey: .server_info)
        serverTimeZone = Self.timeZone(name: server?.nonEmpty(.timezone), timeNow: server?.nonEmpty(.time_now), now: Date())
    }

    /// The zone by name, else the offset between the server's wall clock and now, rounded to 15
    /// minutes (panels without a zone name).
    static func timeZone(name: String?, timeNow: String?, now: Date) -> TimeZone? {
        if let name, let zone = TimeZone(identifier: name) { return zone }
        guard let timeNow else { return nil }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let wall = format.date(from: timeNow) else { return nil }
        let offset = (wall.timeIntervalSince(now) / 900).rounded() * 900
        return TimeZone(secondsFromGMT: Int(offset))
    }
}

public struct XCategory: Identifiable, Hashable, Decodable, Sendable {
    public let id: String
    public let name: String
    /// `name` without provider decoration, with its country and quality tags.
    public let parsed: ChannelName
    public var displayName: String { parsed.name }

    private enum Keys: String, CodingKey { case category_id, category_name }

    public init(id: String, name: String) {
        self.id = id
        self.name = name
        parsed = ChannelName(raw: name, name: name, country: nil, quality: nil)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = c.flexString(.category_id) ?? ""
        name = c.flexString(.category_name) ?? String(localized: "Untitled", bundle: .module)
        parsed = ChannelName.parse(name)
    }
}

public struct LiveChannel: Identifiable, Hashable, Decodable, Sendable {
    public let id: Int
    public let name: String
    public let icon: String?
    public let epgId: String?
    public let categoryId: String?
    public let isAdult: Bool
    public let hasArchive: Bool
    /// Days the provider keeps of this channel (`tv_archive_duration`); 0 without an archive
    /// (catch-up). A channel flagged without a length counts as one day.
    public let archiveDays: Int
    public let searchKey: String
    /// `name` without provider decoration, with its country and quality tags. The search key
    /// stays built from the delivered name.
    public let parsed: ChannelName
    public var displayName: String { parsed.name }
    /// Name with the country, for recordings and their file names: "Das Erste (DE)".
    public var recordingLabel: String { parsed.country.map { "\(parsed.name) (\($0))" } ?? parsed.name }

    private enum Keys: String, CodingKey { case stream_id, name, stream_icon, epg_channel_id, category_id, is_adult, tv_archive, tv_archive_duration }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = c.flexInt(.stream_id) ?? 0
        name = c.flexString(.name)?.trimmingCharacters(in: .whitespaces) ?? ""
        icon = c.nonEmpty(.stream_icon)
        epgId = c.nonEmpty(.epg_channel_id)
        categoryId = c.flexString(.category_id)
        isAdult = c.flexInt(.is_adult) == 1
        hasArchive = c.flexInt(.tv_archive) == 1
        archiveDays = hasArchive ? max(1, c.flexInt(.tv_archive_duration) ?? 1) : 0
        searchKey = makeSearchKey(name)
        parsed = ChannelName.parse(name)
    }

    public static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

public struct Movie: Identifiable, Hashable, Decodable, Sendable {
    public let id: Int
    public let name: String
    public let poster: String?
    public let categoryId: String?
    public let containerExtension: String
    public let rating: Double?
    public let added: Int
    public let isAdult: Bool
    public let searchKey: String

    private enum Keys: String, CodingKey { case stream_id, name, stream_icon, category_id, container_extension, rating, added, is_adult }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = c.flexInt(.stream_id) ?? 0
        name = c.flexString(.name)?.trimmingCharacters(in: .whitespaces) ?? ""
        poster = c.nonEmpty(.stream_icon)
        categoryId = c.flexString(.category_id)
        containerExtension = c.nonEmpty(.container_extension) ?? "mkv"
        rating = c.flexDouble(.rating).flatMap { $0 > 0 ? $0 : nil }
        added = c.flexInt(.added) ?? 0
        isAdult = c.flexInt(.is_adult) == 1
        searchKey = makeSearchKey(name)
    }

    public static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

public struct Series: Identifiable, Hashable, Decodable, Sendable {
    public let id: Int
    public let name: String
    public let cover: String?
    public let plot: String?
    public let cast: String?
    public let genre: String?
    public let releaseDate: String?
    public let rating: Double?
    public let categoryId: String?
    public let lastModified: Int
    public let searchKey: String

    private enum Keys: String, CodingKey { case series_id, name, cover, plot, cast, genre, releaseDate, release_date, rating, category_id, last_modified }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = c.flexInt(.series_id) ?? 0
        name = c.flexString(.name)?.trimmingCharacters(in: .whitespaces) ?? ""
        cover = c.nonEmpty(.cover)
        plot = c.nonEmpty(.plot)
        cast = c.nonEmpty(.cast)
        genre = c.nonEmpty(.genre)
        releaseDate = c.nonEmpty(.releaseDate) ?? c.nonEmpty(.release_date)
        rating = c.flexDouble(.rating).flatMap { $0 > 0 ? $0 : nil }
        categoryId = c.flexString(.category_id)
        lastModified = c.flexInt(.last_modified) ?? 0
        searchKey = makeSearchKey(name)
    }

    public static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

public struct Episode: Identifiable, Hashable, Decodable, Sendable {
    public let id: String
    public let number: Int
    public let season: Int
    public let title: String
    public let containerExtension: String
    public let plot: String?
    public let durationSeconds: Int?
    public let image: String?

    private enum Keys: String, CodingKey { case id, episode_num, season, title, container_extension, info }
    private enum InfoKeys: String, CodingKey { case plot, duration_secs, movie_image }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = c.flexString(.id) ?? UUID().uuidString
        number = c.flexInt(.episode_num) ?? 0
        season = c.flexInt(.season) ?? 0
        title = c.flexString(.title) ?? String(localized: "Episode", bundle: .module)
        containerExtension = c.nonEmpty(.container_extension) ?? "mkv"
        if let info = try? c.nestedContainer(keyedBy: InfoKeys.self, forKey: .info) {
            plot = info.nonEmpty(.plot)
            durationSeconds = info.flexInt(.duration_secs)
            image = info.nonEmpty(.movie_image)
        } else {
            plot = nil
            durationSeconds = nil
            image = nil
        }
    }
}

public struct SeriesInfo: Decodable, Sendable {
    public let seasons: [Int: [Episode]]
    /// All backdrops the provider lists (`backdrop_path` is a list or a single string).
    public let backdrops: [String]
    public var backdrop: String? { backdrops.first }

    private enum Keys: String, CodingKey { case episodes, info }
    private enum InfoKeys: String, CodingKey { case backdrop_path }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        var result: [Int: [Episode]] = [:]
        if let dict = try? c.decode([String: [Episode]].self, forKey: .episodes) {
            for (key, list) in dict { result[Int(key) ?? (list.first?.season ?? 0), default: []] += list }
        } else if let list = try? c.decode([[Episode]].self, forKey: .episodes) {
            for (i, eps) in list.enumerated() { result[eps.first?.season ?? (i + 1), default: []] += eps }
        }
        seasons = result.mapValues { $0.sorted { $0.number < $1.number } }

        if let info = try? c.nestedContainer(keyedBy: InfoKeys.self, forKey: .info) {
            backdrops = info.stringList(.backdrop_path)
        } else {
            backdrops = []
        }
    }
}

public struct MovieDetails: Decodable, Sendable {
    public let plot: String?
    public let genre: String?
    public let cast: String?
    public let director: String?
    public let releaseDate: String?
    public let duration: String?
    public let rating: Double?
    /// All backdrops the provider lists (`backdrop_path` is a list or a single string).
    public let backdrops: [String]
    public var backdrop: String? { backdrops.first }
    public let poster: String?

    private enum Root: String, CodingKey { case info }
    private enum Keys: String, CodingKey {
        case plot, description, genre, cast, actors, director, releasedate, release_date, duration, rating, backdrop_path, movie_image, cover_big
    }

    public init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: Root.self)
        guard let c = try? root.nestedContainer(keyedBy: Keys.self, forKey: .info) else {
            plot = nil; genre = nil; cast = nil; director = nil; releaseDate = nil
            duration = nil; rating = nil; backdrops = []; poster = nil
            return
        }
        plot = c.nonEmpty(.plot) ?? c.nonEmpty(.description)
        genre = c.nonEmpty(.genre)
        cast = c.nonEmpty(.cast) ?? c.nonEmpty(.actors)
        director = c.nonEmpty(.director)
        releaseDate = c.nonEmpty(.releasedate) ?? c.nonEmpty(.release_date)
        duration = c.nonEmpty(.duration)
        rating = c.flexDouble(.rating).flatMap { $0 > 0 ? $0 : nil }
        backdrops = c.stringList(.backdrop_path)
        poster = c.nonEmpty(.movie_image) ?? c.nonEmpty(.cover_big)
    }
}

public struct EPGEntry: Identifiable, Decodable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let start: Date
    public let end: Date

    private enum Keys: String, CodingKey { case id, title, description, start_timestamp, stop_timestamp }

    public init(id: String, title: String, description: String, start: Date, end: Date) {
        self.id = id
        self.title = title
        self.description = description
        self.start = start
        self.end = end
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        title = Self.base64(c.flexString(.title)) ?? ""
        description = Self.base64(c.flexString(.description)) ?? ""
        start = Date(timeIntervalSince1970: TimeInterval(c.flexInt(.start_timestamp) ?? 0))
        end = Date(timeIntervalSince1970: TimeInterval(c.flexInt(.stop_timestamp) ?? 0))
        id = c.flexString(.id) ?? "\(start.timeIntervalSince1970)"
    }

    private static func base64(_ s: String?) -> String? {
        guard let s else { return nil }
        guard let data = Data(base64Encoded: s, options: .ignoreUnknownCharacters),
              let decoded = String(data: data, encoding: .utf8) else { return s }
        return decoded
    }

    public var progress: Double { progress(at: Date()) }

    public func progress(at date: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / total))
    }
}

public struct EPGResponse: Decodable, Sendable {
    public let epg_listings: [EPGEntry]
}
