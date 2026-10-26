import Foundation

public enum XtreamError: LocalizedError, Sendable {
    case invalidServer
    case authFailed
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidServer: return String(localized: "Invalid server address", bundle: .module)
        case .authFailed: return String(localized: "Sign-in failed – wrong username or password", bundle: .module)
        case .http(let code): return String(localized: "Server error (HTTP \(code))", bundle: .module)
        }
    }
}

public enum CatalogAction: String, CaseIterable, Sendable {
    case liveCategories = "get_live_categories"
    case vodCategories = "get_vod_categories"
    case seriesCategories = "get_series_categories"
    case liveStreams = "get_live_streams"
    case vodStreams = "get_vod_streams"
    case series = "get_series"
}

public struct XtreamClient: Sendable {
    public let credentials: XtreamCredentials

    public init(credentials: XtreamCredentials) {
        self.credentials = credentials
    }

    /// Tests replace it with a session whose protocol answers from recorded examples.
    nonisolated(unsafe) static var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    func apiURL(_ action: String?, _ params: [String: String] = [:]) throws -> URL {
        #if DEBUG
        if credentials.isCopied { throw XtreamError.invalidServer }
        #endif
        guard let base = credentials.baseURL,
              var components = URLComponents(url: base.appendingPathComponent("player_api.php"), resolvingAgainstBaseURL: false)
        else { throw XtreamError.invalidServer }
        var items = [URLQueryItem(name: "username", value: credentials.username),
                     URLQueryItem(name: "password", value: credentials.password)]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        items += params.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items
        guard let url = components.url else { throw XtreamError.invalidServer }
        return url
    }

    public func data(_ action: String?, _ params: [String: String] = [:]) async throws -> Data {
        let (data, response) = try await Self.session.data(from: try apiURL(action, params))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw XtreamError.http(http.statusCode)
        }
        return data
    }

    public func account() async throws -> AccountInfo {
        let info = try JSONDecoder().decode(AccountInfo.self, from: try await data(nil))
        guard info.auth else { throw XtreamError.authFailed }
        return info
    }

    public func catalog(_ action: CatalogAction) async throws -> Data {
        try await data(action.rawValue)
    }

    public func seriesInfo(_ id: Int) async throws -> SeriesInfo {
        try JSONDecoder().decode(SeriesInfo.self, from: try await data("get_series_info", ["series_id": String(id)]))
    }

    public func movieDetails(_ id: Int) async throws -> MovieDetails {
        try JSONDecoder().decode(MovieDetails.self, from: try await data("get_vod_info", ["vod_id": String(id)]))
    }

    public func shortEPG(_ streamId: Int, limit: Int = 4) async throws -> [EPGEntry] {
        let d = try await data("get_short_epg", ["stream_id": String(streamId), "limit": String(limit)])
        return (try? JSONDecoder().decode(EPGResponse.self, from: d).epg_listings) ?? []
    }

    /// The full programme the server holds for a channel, including what already aired.
    public func epgTable(_ streamId: Int) async throws -> [EPGEntry] {
        let d = try await data("get_simple_data_table", ["stream_id": String(streamId)])
        return (try? JSONDecoder().decode(EPGResponse.self, from: d).epg_listings) ?? []
    }

    // MARK: Stream URLs

    private func streamURL(_ kind: String, _ id: String, _ ext: String) -> URL? {
        guard let base = credentials.baseURL else { return nil }
        let user = credentials.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? credentials.username
        let pass = credentials.password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? credentials.password
        return URL(string: "\(base.absoluteString)/\(kind)/\(user)/\(pass)/\(id).\(ext)")
    }

    /// Raw MPEG-TS: lowest latency, no HLS segmenting, demuxed directly.
    public func liveURL(_ id: Int) -> URL? { streamURL("live", String(id), "ts") }
    public func movieURL(_ movie: Movie) -> URL? { streamURL("movie", String(movie.id), movie.containerExtension) }
    public func episodeURL(_ episode: Episode) -> URL? { streamURL("series", episode.id, episode.containerExtension) }
}
