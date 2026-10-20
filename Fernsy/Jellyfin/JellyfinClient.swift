import Foundation

/// Jellyfin REST client. All routes live here; they were verified against Jellyfin 12.2.0,
/// which answers both the older `/Users/{id}/…` and the newer user-less forms – we use the
/// newer ones (`/UserItems/…`, `/UserPlayedItems/…`, `/Items?userId=`).
struct JellyfinClient {
    let base: URL
    var token: String?

    static let clientName = "Fernsy"

    /// Created once per installation; the server lists Fernsy as this device.
    static var deviceId: String {
        let key = "jellyfin.deviceId"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    static let deviceName: String = Host.current().localizedName ?? "Mac"

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
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

    private func request(_ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil) async throws -> Data {
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
        let (data, response) = try await Self.session.data(for: req)
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
    static let detailFields = "Genres,DateCreated,PremiereDate,ProductionYear,CommunityRating,OfficialRating,Overview,People,MediaSources,ChildCount,RecursiveItemCount"

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

