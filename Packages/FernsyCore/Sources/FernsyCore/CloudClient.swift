import Foundation

/// The Fernsy Cloud API (add-recording-cloud design E, `cloud-server/README.md`). The account is
/// the cloud key's account id and access secret (cloud-account-from-icloud-key design A); there
/// is no sign-in and nothing of it is stored apart from the key.
///
/// Debug builds: `IPTV_CLOUD=<server URL>` picks the server, `IPTV_CLOUDTOKEN=<dev token>` uses
/// the development server's fixed user instead of a key.
public final class CloudClient: @unchecked Sendable {
    public static let productionURL = URL(string: "https://fernsy-cloud.mobilistics.workers.dev")!

    public struct Account: Codable, Equatable, Sendable {
        public enum State: String, Codable, Sendable { case none, active, grace, ended }
        public var userId: String?
        public var state: State
        public var expiresAt: Date?
        public var endedAt: Date?
        public var deleteAt: Date?
        public var usedBytes: Int64
        public var totalBytes: Int64

        public init(userId: String? = nil, state: State, expiresAt: Date? = nil, endedAt: Date? = nil, deleteAt: Date? = nil,
                    usedBytes: Int64 = 0, totalBytes: Int64 = 0) {
            self.userId = userId
            self.state = state
            self.expiresAt = expiresAt
            self.endedAt = endedAt
            self.deleteAt = deleteAt
            self.usedBytes = usedBytes
            self.totalBytes = totalBytes
        }

        public var canUpload: Bool { state == .active }
        public var canPlay: Bool { state == .active || state == .grace }
        public var freeBytes: Int64 { max(0, totalBytes - usedBytes) }
    }

    public struct Recording: Codable, Equatable, Sendable {
        public var id: String
        public var dataBytes: Int64
        public var metaBytes: Int64
        public var completedAt: Date
    }

    public struct PartURL: Codable, Equatable, Sendable {
        public var number: Int
        public var url: URL
    }

    public struct Upload: Codable, Equatable, Sendable {
        public var id: String
        public var uploadId: String
        public var partSize: Int
        public var partCount: Int
        public var partURLs: [PartURL]
        public var metaURL: URL
    }

    public struct CompletedPart: Codable, Equatable, Sendable {
        public var number: Int
        public var etag: String
        public init(number: Int, etag: String) {
            self.number = number
            self.etag = etag
        }
    }

    public struct ReadURLs: Codable, Equatable, Sendable {
        public var dataURL: URL
        public var metaURL: URL
        public var expiresAt: Date
    }

    public enum Failure: Error, Equatable {
        /// No key on this device yet, so no account to ask for.
        case noAccount
        /// The server knows this account id with another secret (design risks: squatting).
        case accountConflict
        case noSubscription
        case quota(needed: Int64, free: Int64)
        case notFound
        /// The subscription was bought for another account or without one; it can be moved.
        case otherAccount
        case appleNotConfigured
        case server(status: Int, code: String)
        case network(String)
    }

    public enum Credential: Equatable, Sendable {
        case none
        /// `Authorization: Key <accountId>:<base64url secret>`.
        case key(accountId: String, secret: Data)
        /// The development server's token (`Authorization: Dev …`).
        case dev(String)
    }

    public let baseURL: URL
    private let urlSession: URLSession
    private let lock = NSLock()
    private var credential: Credential

    public init(baseURL: URL, urlSession: URLSession = .shared, credential: Credential) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.credential = credential
    }

    /// The server from `IPTV_CLOUD` (debug) or production; the dev token when given, otherwise
    /// no account until `use(_:)` hands over the key.
    public static func live() -> CloudClient {
        var base = productionURL
        var credential: Credential = .none
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let text = env["IPTV_CLOUD"], let url = URL(string: text) { base = url }
        if let token = env["IPTV_CLOUDTOKEN"], !token.isEmpty { credential = .dev(token) }
        #endif
        return CloudClient(baseURL: base, credential: credential)
    }

    /// The account of this key from now on (the dev token, when set, stays).
    public func use(_ key: CloudAccountKey) {
        lock.withLock {
            if case .dev = credential { return }
            credential = .key(accountId: key.accountId, secret: key.accessSecret)
        }
    }

    public var hasAccount: Bool { lock.withLock { credential != .none } }
    public var isDevelopment: Bool { lock.withLock { if case .dev = credential { true } else { false } } }

    // MARK: Account

    /// The account's state; the first call with a new key registers it (design B).
    public func account() async throws -> Account { try await send("GET", "v1/account") }

    /// Links the subscription to this account; `move` takes it over from another account
    /// (design E), which the app offers only after `otherAccount`.
    public func linkSubscription(originalTransactionId: String, move: Bool = false) async throws -> Account {
        struct Body: Encodable { var originalTransactionId: String; var move: Bool? }
        return try await send("POST", "v1/subscription", body: Body(originalTransactionId: originalTransactionId, move: move ? true : nil))
    }

    /// Deletes every recording and the account on the server (design G). The key stays, so the
    /// next request starts a new, empty account and gets the subscription back.
    public func deleteAccount() async throws {
        let _: Empty = try await send("DELETE", "v1/account")
    }

    // MARK: Recordings

    private struct RecordingList: Decodable { var recordings: [Recording] }
    private struct Completed: Decodable { var id: String; var dataBytes: Int64 }

    public func recordings() async throws -> [Recording] {
        let list: RecordingList = try await send("GET", "v1/recordings")
        return list.recordings
    }

    public func startUpload(dataBytes: Int64, metaBytes: Int64, partSize: Int = CloudCrypto.partSize) async throws -> Upload {
        try await send("POST", "v1/recordings", body: ["dataBytes": dataBytes, "metaBytes": metaBytes, "partSize": Int64(partSize)])
    }

    /// Fresh part URLs (the server signs at most 50 per request, the start answer only the first
    /// 20), and with `meta` a fresh URL for the details.
    public func partURLs(id: String, numbers: [Int], meta: Bool = false) async throws -> (parts: [PartURL], metaURL: URL?) {
        struct Body: Encodable { var numbers: [Int]; var meta: Bool? }
        struct Answer: Decodable { var partURLs: [PartURL]; var metaURL: URL? }
        let answer: Answer = try await send("POST", "v1/recordings/\(id)/parts", body: Body(numbers: numbers, meta: meta ? true : nil))
        return (answer.partURLs, answer.metaURL)
    }

    /// Most part URLs one `partURLs` request returns.
    public static let partURLBatch = 50

    public func complete(id: String, parts: [CompletedPart]) async throws {
        struct Body: Encodable { var parts: [CompletedPart] }
        let _: Completed = try await send("POST", "v1/recordings/\(id)/complete", body: Body(parts: parts))
    }

    public func readURLs(id: String) async throws -> ReadURLs { try await send("GET", "v1/recordings/\(id)/urls") }

    public func delete(id: String) async throws {
        let _: Empty = try await send("DELETE", "v1/recordings/\(id)")
    }

    // MARK: Development server

    /// Dev server only: sets the dev user's subscription state, for UI tests and manual checks.
    public func devSetAccount(state: String, endedDaysAgo: Int? = nil, quotaBytes: Int64? = nil) async throws {
        struct Body: Encodable { var state: String; var endedDaysAgo: Int?; var quotaBytes: Int64? }
        let _: Empty = try await send("POST", "v1/dev/account", body: Body(state: state, endedDaysAgo: endedDaysAgo, quotaBytes: quotaBytes))
    }

    // MARK: Transport

    struct Empty: Decodable {}
    private struct ErrorAnswer: Decodable {
        var error: String
        var neededBytes: Int64?
        var freeBytes: Int64?
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 30
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        switch lock.withLock({ credential }) {
        case .none: throw Failure.noAccount
        case .key(let id, let secret): request.setValue("Key \(id):\(secret.base64URL)", forHTTPHeaderField: "Authorization")
        case .dev(let token): request.setValue("Dev \(token)", forHTTPHeaderField: "Authorization")
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let answer = try? JSONDecoder().decode(ErrorAnswer.self, from: data)
            let code = answer?.error ?? ""
            AppLog.detail(.app, "Fernsy Cloud: \(method) \(path.split(separator: "/").prefix(2).joined(separator: "/")) → \(status) \(code)")
            switch (status, code) {
            case (401, _): throw Failure.accountConflict
            case (402, _): throw Failure.noSubscription
            case (413, _): throw Failure.quota(needed: answer?.neededBytes ?? 0, free: answer?.freeBytes ?? 0)
            case (404, _): throw Failure.notFound
            case (409, _): throw Failure.otherAccount
            case (503, "apple_not_configured"): throw Failure.appleNotConfigured
            default: throw Failure.server(status: status, code: code)
            }
        }
        if T.self == Empty.self { return Empty() as! T }
        return try JSONDecoder.cloud.decode(T.self, from: data)
    }
}

extension Data {
    /// Base64 without padding, `-` and `_` instead of `+` and `/`.
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
