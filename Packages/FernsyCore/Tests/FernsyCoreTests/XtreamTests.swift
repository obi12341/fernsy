import Foundation
import Testing
@testable import FernsyCore

/// Recorded answers of the demo server (Fixtures/xtream, recorded once with the public demo
/// account; lists cut to five entries).
enum XtreamFixtures {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/xtream"))
        return try Data(contentsOf: url)
    }
}

/// Decoding the provider's JSON into the catalog's models.
struct XtreamDecodingTests {
    @Test func account() throws {
        let info = try JSONDecoder().decode(AccountInfo.self, from: try XtreamFixtures.data("account"))
        #expect(info.auth)
        #expect(info.status == "Active")
        #expect(info.maxConnections == 5)
        #expect(info.expiresAt != nil)
    }

    @Test func liveChannels() throws {
        let channels = try JSONDecoder().decode([LiveChannel].self, from: try XtreamFixtures.data("get_live_streams"))
        #expect(channels.count == 5)
        let first = try #require(channels.first)
        #expect(first.id == 101)
        #expect(!first.displayName.isEmpty)
        #expect(first.categoryId != nil)
    }

    @Test(arguments: ["get_live_categories", "get_vod_categories", "get_series_categories"])
    func categories(_ fixture: String) throws {
        let categories = try JSONDecoder().decode([XCategory].self, from: try XtreamFixtures.data(fixture))
        #expect(!categories.isEmpty)
        #expect(categories.allSatisfy { !$0.id.isEmpty && !$0.displayName.isEmpty })
    }

    @Test func moviesAndSeries() throws {
        let movies = try JSONDecoder().decode([Movie].self, from: try XtreamFixtures.data("get_vod_streams"))
        #expect(movies.count == 5)
        #expect(movies.allSatisfy { !$0.containerExtension.isEmpty })
        let series = try JSONDecoder().decode([Series].self, from: try XtreamFixtures.data("get_series"))
        #expect(series.count == 5)
    }

    @Test func seriesInfoAndMovieDetails() throws {
        let info = try JSONDecoder().decode(SeriesInfo.self, from: try XtreamFixtures.data("get_series_info"))
        #expect(!info.seasons.isEmpty)
        #expect(info.seasons.values.allSatisfy { !$0.isEmpty })
        let details = try JSONDecoder().decode(MovieDetails.self, from: try XtreamFixtures.data("get_vod_info"))
        #expect(details.plot != nil || details.genre != nil)
    }

    @Test(arguments: ["get_short_epg", "get_simple_data_table"])
    func guide(_ fixture: String) throws {
        let entries = try JSONDecoder().decode(EPGResponse.self, from: try XtreamFixtures.data(fixture)).epg_listings
        #expect(!entries.isEmpty)
        // Titles come base64-encoded and are decoded.
        #expect(entries.allSatisfy { !$0.title.isEmpty && !$0.title.hasSuffix("=") && $0.start < $0.end })
    }
}

/// Answers every request from the fixtures, so no request leaves the machine. The username
/// picks a failure: "http401", "noauth", "badjson".
final class XtreamStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var unexpected: [URL] = []
    static let lock = NSLock()

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [XtreamStub.self]
        return URLSession(configuration: config)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let user = query.first { $0.name == "username" }?.value
        let action = query.first { $0.name == "action" }?.value
        var status = 200
        var body = Data()
        switch (user, action) {
        case ("http401", _): status = 401
        case ("noauth", nil): body = Data(#"{"user_info":{"auth":0}}"#.utf8)
        case ("badjson", _): body = Data("<html>not json</html>".utf8)
        case (_, let action):
            if url.host == "demo.test", let data = try? XtreamFixtures.data(action ?? "account") {
                body = data
            } else {
                Self.lock.lock(); Self.unexpected.append(url); Self.lock.unlock()
                status = 404
            }
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// The client against the stub: URLs, decoding, errors, and no credentials in the log.
@Suite(.serialized)
struct XtreamClientTests {
    init() { XtreamClient.session = XtreamStub.session }

    static func client(_ user: String = "demo") -> XtreamClient {
        XtreamClient(credentials: XtreamCredentials(server: "https://demo.test", username: user, password: "s3cr3t-Pass"))
    }

    @Test func accountAndCatalog() async throws {
        let client = Self.client()
        let info = try await client.account()
        #expect(info.maxConnections == 5)
        let channels = try JSONDecoder().decode([LiveChannel].self, from: try await client.catalog(.liveStreams))
        #expect(channels.first?.id == 101)
        #expect(!(try await client.shortEPG(101)).isEmpty)
        #expect(!(try await client.seriesInfo(1)).seasons.isEmpty)
        #expect(XtreamStub.unexpected.isEmpty, "requests outside the stub: \(XtreamStub.unexpected)")
    }

    @Test func requestURL() throws {
        let url = try Self.client().apiURL("get_short_epg", ["stream_id": "101"])
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.path == "/player_api.php")
        #expect(items.contains(URLQueryItem(name: "action", value: "get_short_epg")))
        #expect(items.contains(URLQueryItem(name: "stream_id", value: "101")))
    }

    @Test func httpErrorIsReported() async {
        await #expect(throws: XtreamError.self) { try await Self.client("http401").account() }
        do {
            _ = try await Self.client("http401").account()
        } catch {
            #expect(error.localizedDescription.contains("401"))
            #expect(!error.localizedDescription.contains("s3cr3t-Pass"))
        }
    }

    @Test func refusedSignIn() async {
        do {
            _ = try await Self.client("noauth").account()
            Issue.record("sign-in should fail")
        } catch let error as XtreamError {
            guard case .authFailed = error else { Issue.record("expected authFailed, got \(error)"); return }
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func invalidJSONThrows() async {
        await #expect(throws: (any Error).self) { try await Self.client("badjson").account() }
    }

    @Test func requestURLsAreRedactedInTheLog() throws {
        let url = try Self.client().apiURL("get_live_streams")
        let logged = AppLog.shared.redact("GET \(url.absoluteString) failed", secrets: [])
        #expect(!logged.contains("s3cr3t-Pass"))
        #expect(!logged.contains("username=demo"))
        let stream = try #require(Self.client().liveURL(101))
        #expect(!AppLog.shared.redact(stream.absoluteString, secrets: []).contains("s3cr3t-Pass"))
    }
}
