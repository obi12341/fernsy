import FernsyCore
import Foundation

// Xtream Codes panels are loose with JSON types (ids as strings or ints, numbers
// as strings, null vs ""), so everything decodes leniently.
extension KeyedDecodingContainer {
    func flexString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }

    func flexInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) ?? Double(s).map { Int($0) } }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        return nil
    }

    func flexDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }

    func nonEmpty(_ key: Key) -> String? {
        guard let s = flexString(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

func makeSearchKey(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
}

struct XtreamCredentials: Codable, Equatable {
    var server: String
    var username: String
    var password: String

    var baseURL: URL? {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s)
    }

    #if DEBUG
    /// IPTV_COPIEDACCOUNT: an account folder copied from the installed app, opened without its
    /// credentials (they stay in the installed app's keychain). The server never resolves.
    static let copiedServer = "http://copied-account.invalid"
    static var copied: XtreamCredentials? {
        guard let folder = ProcessInfo.processInfo.environment["IPTV_COPIEDACCOUNT"], !folder.isEmpty else { return nil }
        return XtreamCredentials(server: copiedServer, username: folder, password: "")
    }
    var isCopied: Bool { server == Self.copiedServer }
    #endif

    /// Stable identifier for per-account cache folders.
    var accountKey: String {
        #if DEBUG
        if isCopied { return username }
        #endif
        let raw = "\(server.lowercased())|\(username)"
        return String(raw.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" })
    }
}

struct AccountInfo: Decodable {
    let auth: Bool
    let status: String?
    let expiresAt: Date?
    let maxConnections: Int?
    let activeConnections: Int?

    private enum Root: String, CodingKey { case user_info }
    private enum Keys: String, CodingKey { case auth, status, exp_date, max_connections, active_cons }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: Root.self)
        let c = try root.nestedContainer(keyedBy: Keys.self, forKey: .user_info)
        auth = c.flexInt(.auth) == 1
        status = c.flexString(.status)
        expiresAt = c.flexInt(.exp_date).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        maxConnections = c.flexInt(.max_connections)
        activeConnections = c.flexInt(.active_cons)
    }
}

struct XCategory: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    /// `name` without provider decoration, with its country and quality tags.
    let parsed: ChannelName
    var displayName: String { parsed.name }

    private enum Keys: String, CodingKey { case category_id, category_name }

    init(id: String, name: String) {
        self.id = id
        self.name = name
        parsed = ChannelName(raw: name, name: name, country: nil, quality: nil)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = c.flexString(.category_id) ?? ""
        name = c.flexString(.category_name) ?? String(localized: "Untitled")
        parsed = ChannelName.parse(name)
    }
}

struct LiveChannel: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
    let icon: String?
    let epgId: String?
    let categoryId: String?
    let isAdult: Bool
    let hasArchive: Bool
    let searchKey: String
    /// `name` without provider decoration, with its country and quality tags. The search key
    /// stays built from the delivered name.
    let parsed: ChannelName
    var displayName: String { parsed.name }
    /// Name with the country, for recordings and their file names: "Das Erste (DE)".
    var recordingLabel: String { parsed.country.map { "\(parsed.name) (\($0))" } ?? parsed.name }

    private enum Keys: String, CodingKey { case stream_id, name, stream_icon, epg_channel_id, category_id, is_adult, tv_archive }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = c.flexInt(.stream_id) ?? 0
        name = c.flexString(.name)?.trimmingCharacters(in: .whitespaces) ?? ""
        icon = c.nonEmpty(.stream_icon)
        epgId = c.nonEmpty(.epg_channel_id)
        categoryId = c.flexString(.category_id)
        isAdult = c.flexInt(.is_adult) == 1
        hasArchive = c.flexInt(.tv_archive) == 1
        searchKey = makeSearchKey(name)
        parsed = ChannelName.parse(name)
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Movie: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
    let poster: String?
    let categoryId: String?
    let containerExtension: String
    let rating: Double?
    let added: Int
    let isAdult: Bool
    let searchKey: String

    private enum Keys: String, CodingKey { case stream_id, name, stream_icon, category_id, container_extension, rating, added, is_adult }

    init(from decoder: Decoder) throws {
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

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Series: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
    let cover: String?
    let plot: String?
    let cast: String?
    let genre: String?
    let releaseDate: String?
    let rating: Double?
    let categoryId: String?
    let lastModified: Int
    let searchKey: String

    private enum Keys: String, CodingKey { case series_id, name, cover, plot, cast, genre, releaseDate, release_date, rating, category_id, last_modified }

    init(from decoder: Decoder) throws {
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

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Episode: Identifiable, Hashable, Decodable {
    let id: String
    let number: Int
    let season: Int
    let title: String
    let containerExtension: String
    let plot: String?
    let durationSeconds: Int?
    let image: String?

    private enum Keys: String, CodingKey { case id, episode_num, season, title, container_extension, info }
    private enum InfoKeys: String, CodingKey { case plot, duration_secs, movie_image }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = c.flexString(.id) ?? UUID().uuidString
        number = c.flexInt(.episode_num) ?? 0
        season = c.flexInt(.season) ?? 0
        title = c.flexString(.title) ?? String(localized: "Episode")
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

struct SeriesInfo: Decodable {
    let seasons: [Int: [Episode]]
    let backdrop: String?

    private enum Keys: String, CodingKey { case episodes, info }
    private enum InfoKeys: String, CodingKey { case backdrop_path }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        var result: [Int: [Episode]] = [:]
        if let dict = try? c.decode([String: [Episode]].self, forKey: .episodes) {
            for (key, list) in dict { result[Int(key) ?? (list.first?.season ?? 0), default: []] += list }
        } else if let list = try? c.decode([[Episode]].self, forKey: .episodes) {
            for (i, eps) in list.enumerated() { result[eps.first?.season ?? (i + 1), default: []] += eps }
        }
        seasons = result.mapValues { $0.sorted { $0.number < $1.number } }

        if let info = try? c.nestedContainer(keyedBy: InfoKeys.self, forKey: .info) {
            if let list = try? info.decode([String].self, forKey: .backdrop_path) { backdrop = list.first }
            else { backdrop = info.nonEmpty(.backdrop_path) }
        } else {
            backdrop = nil
        }
    }
}

struct MovieDetails: Decodable {
    let plot: String?
    let genre: String?
    let cast: String?
    let director: String?
    let releaseDate: String?
    let duration: String?
    let rating: Double?
    let backdrop: String?
    let poster: String?

    private enum Root: String, CodingKey { case info }
    private enum Keys: String, CodingKey {
        case plot, description, genre, cast, actors, director, releasedate, release_date, duration, rating, backdrop_path, movie_image, cover_big
    }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: Root.self)
        guard let c = try? root.nestedContainer(keyedBy: Keys.self, forKey: .info) else {
            plot = nil; genre = nil; cast = nil; director = nil; releaseDate = nil
            duration = nil; rating = nil; backdrop = nil; poster = nil
            return
        }
        plot = c.nonEmpty(.plot) ?? c.nonEmpty(.description)
        genre = c.nonEmpty(.genre)
        cast = c.nonEmpty(.cast) ?? c.nonEmpty(.actors)
        director = c.nonEmpty(.director)
        releaseDate = c.nonEmpty(.releasedate) ?? c.nonEmpty(.release_date)
        duration = c.nonEmpty(.duration)
        rating = c.flexDouble(.rating).flatMap { $0 > 0 ? $0 : nil }
        if let list = try? c.decode([String].self, forKey: .backdrop_path) { backdrop = list.first }
        else { backdrop = c.nonEmpty(.backdrop_path) }
        poster = c.nonEmpty(.movie_image) ?? c.nonEmpty(.cover_big)
    }
}

struct EPGEntry: Identifiable, Decodable {
    let id: String
    let title: String
    let description: String
    let start: Date
    let end: Date

    private enum Keys: String, CodingKey { case id, title, description, start_timestamp, stop_timestamp }

    init(id: String, title: String, description: String, start: Date, end: Date) {
        self.id = id
        self.title = title
        self.description = description
        self.start = start
        self.end = end
    }

    init(from decoder: Decoder) throws {
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

    var progress: Double { progress(at: Date()) }

    func progress(at date: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / total))
    }
}

struct EPGResponse: Decodable {
    let epg_listings: [EPGEntry]
}
