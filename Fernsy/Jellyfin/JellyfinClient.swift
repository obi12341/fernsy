import FernsyCore
import Foundation

/// Jellyfin REST client. All routes live here; they were verified against Jellyfin 12.2.0,
/// which answers both the older `/Users/{id}/…` and the newer user-less forms – we use the
/// newer ones (`/UserItems/…`, `/UserPlayedItems/…`, `/Items?userId=`).
struct JellyfinClient {
    let base: URL
    var token: String?

    static let clientName = "Fernsy"

    /// Created once per installation; the server lists Fernsy as this device. Debug builds
    /// share UserDefaults with the installed app but must be another device: signing in ends
    /// the other sessions of the same device on the server.
    static var deviceId: String {
        #if DEBUG
        let key = "jellyfin.deviceId.debug"
        #else
        let key = "jellyfin.deviceId"
        #endif
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    #if DEBUG
    static let deviceName: String = (Host.current().localizedName ?? "Mac") + " (Debug)"
    #else
    static let deviceName: String = Host.current().localizedName ?? "Mac"
    #endif

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Subtitle files: on the first request the server extracts an embedded track from the whole
    /// file before it sends anything, which can take well over the usual 20 s.
    private static let slowSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Server JSON is PascalCase; our models are camelCase.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .custom { keys in
            let last = keys.last!.stringValue
            return AnyKey(last.prefix(1).lowercased() + last.dropFirst())
        }
        return d
    }()

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    var authorization: String {
        var value = "MediaBrowser Client=\"\(Self.clientName)\", Device=\"\(Self.deviceName)\", DeviceId=\"\(Self.deviceId)\", Version=\"\(Self.appVersion)\""
        if let token { value += ", Token=\"\(token)\"" }
        return value
    }

    // MARK: Requests

    private func request(_ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil,
                         session: URLSession = JellyfinClient.session) async throws -> Data {
        guard var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw JellyfinError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw JellyfinError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw JellyfinError.unauthorized }
        guard (200..<300).contains(status) else { throw JellyfinError.http(status) }
        return data
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        try Self.decoder.decode(T.self, from: try await request("GET", path, query: query))
    }

    // MARK: Server and session

    func publicInfo() async throws -> JFPublicInfo {
        let info: JFPublicInfo
        do {
            info = try await get("System/Info/Public")
        } catch let error as JellyfinError {
            throw error == .unauthorized ? error : JellyfinError.notJellyfin
        } catch is DecodingError {
            throw JellyfinError.notJellyfin
        }
        guard info.productName?.localizedCaseInsensitiveContains("Jellyfin") == true, info.id != nil else {
            throw JellyfinError.notJellyfin
        }
        return info
    }

    func authenticate(username: String, password: String) async throws -> JFAuthResult {
        let body = try JSONSerialization.data(withJSONObject: ["Username": username, "Pw": password])
        do {
            return try Self.decoder.decode(JFAuthResult.self, from: try await request("POST", "Users/AuthenticateByName", body: body))
        } catch JellyfinError.unauthorized {
            throw JellyfinError.wrongCredentials
        }
    }

    func logout() async {
        _ = try? await request("POST", "Sessions/Logout")
    }

    // MARK: Library

    static let gridFields = "Genres,DateCreated,PremiereDate,ProductionYear,CommunityRating,OfficialRating,SortName,RecursiveItemCount,ChildCount"
    static let detailFields = "Genres,DateCreated,PremiereDate,ProductionYear,CommunityRating,OfficialRating,Overview,People,MediaSources,MediaStreams,ChildCount,RecursiveItemCount"

    /// Libraries of the user (films, series, music, …).
    func views(userId: String) async throws -> [JFItem] {
        let page: JFItemsPage = try await get("UserViews", ["userId": userId])
        return page.items
    }

    /// One page of films or series of a library.
    func items(userId: String, parentId: String, type: String, start: Int, limit: Int) async throws -> JFItemsPage {
        try await get("Items", [
            "userId": userId, "parentId": parentId, "includeItemTypes": type, "recursive": "true",
            "fields": Self.gridFields, "enableImageTypes": "Primary,Backdrop,Thumb",
            "startIndex": String(start), "limit": String(limit), "enableTotalRecordCount": "true",
            "sortBy": "SortName", "sortOrder": "Ascending",
        ])
    }

    /// Watched state and favorites only, for a quick refresh of a whole library.
    func userData(userId: String, parentId: String, type: String) async throws -> [JFItem] {
        let page: JFItemsPage = try await get("Items", [
            "userId": userId, "parentId": parentId, "includeItemTypes": type, "recursive": "true",
            "fields": "RecursiveItemCount", "enableImages": "false",
        ])
        return page.items
    }

    func item(userId: String, id: String) async throws -> JFItem {
        try await get("Items/\(id)", ["userId": userId])
    }

    func seasons(userId: String, seriesId: String) async throws -> [JFItem] {
        let page: JFItemsPage = try await get("Shows/\(seriesId)/Seasons", ["userId": userId, "fields": "ChildCount,RecursiveItemCount"])
        return page.items
    }

    func episodes(userId: String, seriesId: String, seasonId: String) async throws -> [JFItem] {
        let page: JFItemsPage = try await get("Shows/\(seriesId)/Episodes", [
            "userId": userId, "seasonId": seasonId, "fields": "Overview,PremiereDate",
        ])
        return page.items
    }

    func resume(userId: String) async throws -> [JFItem] {
        let page: JFItemsPage = try await get("UserItems/Resume", [
            "userId": userId, "limit": "24", "mediaTypes": "Video", "includeItemTypes": "Movie,Episode",
            "fields": "PremiereDate,ProductionYear",
        ])
        return page.items
    }

    func nextUp(userId: String) async throws -> [JFItem] {
        let page: JFItemsPage = try await get("Shows/NextUp", ["userId": userId, "limit": "24", "fields": "PremiereDate"])
        return page.items
    }

    func latest(userId: String, parentId: String) async throws -> [JFItem] {
        try await get("Items/Latest", ["userId": userId, "parentId": parentId, "limit": "24", "fields": Self.gridFields])
    }

    // MARK: User data

    /// Returns the item's new user data.
    /// Callers must only pass films, series, seasons or episodes (see `JellyfinStore.markableTypes`):
    /// on folders the server marks every item below.
    func setPlayed(userId: String, itemId: String, played: Bool) async throws -> JFUserData {
        let data = try await request(played ? "POST" : "DELETE", "UserPlayedItems/\(itemId)", query: ["userId": userId])
        return try Self.decoder.decode(JFUserData.self, from: data)
    }

    func setFavorite(userId: String, itemId: String, favorite: Bool) async throws -> JFUserData {
        let data = try await request(favorite ? "POST" : "DELETE", "UserFavoriteItems/\(itemId)", query: ["userId": userId])
        return try Self.decoder.decode(JFUserData.self, from: data)
    }

    // MARK: Playback

    /// The original file (direct play, range requests). The token goes into the query because
    /// the player's byte source sends no auth header; never log this URL.
    func directStreamURL(itemId: String, mediaSourceId: String) -> URL? {
        var c = URLComponents(url: base.appendingPathComponent("Videos/\(itemId)/stream"), resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "static", value: "true"), URLQueryItem(name: "mediaSourceId", value: mediaSourceId),
                         URLQueryItem(name: "api_key", value: token)]
        return c?.url
    }

    /// Progressive transcode (no HLS: the player cannot read it). Every stream index is explicit
    /// – without a subtitle index the server picks its default track, and a bitmap one means a
    /// burn-in transcode. Dolby Vision is excluded so the server tone-maps it.
    func transcode(userId: String, itemId: String, mediaSourceId: String, startSeconds: Double,
                   audioIndex: Int?, subtitleIndex: Int?, container: String) async throws -> (url: URL, playSessionId: String?) {
        let profile: [String: Any] = [
            "Name": "Fernsy",
            "MaxStreamingBitrate": 120_000_000,
            "DirectPlayProfiles": [] as [Any],
            "TranscodingProfiles": [[
                "Container": container, "Type": "Video", "VideoCodec": "h264,hevc", "AudioCodec": "aac,ac3,eac3",
                "Protocol": "http", "Context": "Streaming", "MaxAudioChannels": "6", "CopyTimestamps": false,
            ]],
            "CodecProfiles": [[
                "Type": "Video",
                "Conditions": [["Condition": "EqualsAny", "Property": "VideoRangeType", "Value": "SDR|HDR10|HLG", "IsRequired": true]],
            ]],
            "SubtitleProfiles": [["Format": "srt", "Method": "External"], ["Format": "subrip", "Method": "External"],
                                 ["Format": "pgssub", "Method": "Encode"], ["Format": "dvdsub", "Method": "Encode"]],
        ]
        var body: [String: Any] = [
            "UserId": userId, "MediaSourceId": mediaSourceId, "DeviceProfile": profile,
            "StartTimeTicks": Int64(startSeconds * 10_000_000), "EnableDirectPlay": false, "EnableDirectStream": false,
            "EnableTranscoding": true, "AllowVideoStreamCopy": false, "AllowAudioStreamCopy": true, "AutoOpenLiveStream": false,
            "SubtitleStreamIndex": subtitleIndex ?? -1,
        ]
        if let audioIndex { body["AudioStreamIndex"] = audioIndex }
        let data = try await request("POST", "Items/\(itemId)/PlaybackInfo", query: ["userId": userId],
                                     body: try JSONSerialization.data(withJSONObject: body))
        let info = try Self.decoder.decode(JFPlaybackInfo.self, from: data)
        guard let path = info.mediaSources.first?.transcodingUrl,
              let url = URL(string: path, relativeTo: base.appendingPathComponent("/"))?.absoluteURL else {
            throw JellyfinError.http(422)
        }
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = c?.queryItems ?? []
        if !items.contains(where: { $0.name.lowercased() == "api_key" }) {
            c?.queryItems = items + [URLQueryItem(name: "api_key", value: token)]
        }
        return (c?.url ?? url, info.playSessionId)
    }

    /// Ends the server's transcode for this device and play session.
    func stopTranscode(playSessionId: String?) async throws {
        var query = ["deviceId": Self.deviceId]
        if let playSessionId { query["playSessionId"] = playSessionId }
        _ = try await request("DELETE", "Videos/ActiveEncodings", query: query)
    }

    enum ProgressEvent: String { case start = "Sessions/Playing", progress = "Sessions/Playing/Progress", stopped = "Sessions/Playing/Stopped" }

    func report(_ event: ProgressEvent, itemId: String, mediaSourceId: String, positionSeconds: Double, isPaused: Bool,
                transcoding: Bool, playSessionId: String?, audioIndex: Int?, subtitleIndex: Int?) async throws {
        var body: [String: Any] = [
            "ItemId": itemId, "MediaSourceId": mediaSourceId, "PositionTicks": Int64(max(0, positionSeconds) * 10_000_000),
            "IsPaused": isPaused, "PlayMethod": transcoding ? "Transcode" : "DirectPlay", "CanSeek": true,
            "SubtitleStreamIndex": subtitleIndex ?? -1,
        ]
        if let playSessionId { body["PlaySessionId"] = playSessionId }
        if let audioIndex { body["AudioStreamIndex"] = audioIndex }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        _ = try await request("POST", event.rawValue, body: data)
    }

    func pingTranscode(playSessionId: String) async throws {
        _ = try await request("POST", "Sessions/Playing/Ping", query: ["playSessionId": playSessionId])
    }

    /// A text subtitle stream converted to SRT by the server (embedded or external).
    func subtitleSRT(itemId: String, mediaSourceId: String, index: Int) async throws -> String {
        let data = try await request("GET", "Videos/\(itemId)/\(mediaSourceId)/Subtitles/\(index)/0/Stream.srt", session: Self.slowSession)
        return String(decoding: data, as: UTF8.self)
    }

    /// Every episode of a series, all seasons and specials (for neighbours and episode lists).
    func seriesEpisodes(userId: String, seriesId: String) async throws -> [JFItem] {
        let page: JFItemsPage = try await get("Shows/\(seriesId)/Episodes", ["userId": userId, "fields": "PremiereDate"])
        return page.items
    }

    /// The episode after `episodeId` in the series' order, if any.
    func nextEpisode(userId: String, seriesId: String, after episodeId: String) async throws -> JFItem? {
        let page: JFItemsPage = try await get("Shows/\(seriesId)/Episodes", ["userId": userId, "startItemId": episodeId, "limit": "2"])
        return page.items.count > 1 ? page.items[1] : nil
    }

    // MARK: Images

    /// Artwork URL; the tag makes the URL change when the artwork changes (URL-keyed cache).
    func imageURL(itemId: String, type: String, tag: String?, maxHeight: Int) -> String? {
        guard let tag else { return nil }
        var components = URLComponents(url: base.appendingPathComponent("Items/\(itemId)/Images/\(type)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "tag", value: tag), URLQueryItem(name: "maxHeight", value: String(maxHeight)),
                                  URLQueryItem(name: "quality", value: "90")]
        return components?.url?.absoluteString
    }
}

