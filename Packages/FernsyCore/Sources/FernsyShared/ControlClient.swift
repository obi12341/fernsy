import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The Fernsy Control worker's API (control-server/README.md): sealed items per space and the
/// pairing mailbox. Shared by the apps and Fernsy Server.
public final class ControlClient: Sendable {
    public static let productionURL = URL(string: "https://fernsy-control.mobilistics.workers.dev")!

    public enum Failure: Error, Equatable {
        case network(String)
        case server(status: Int, code: String)
        case notFound
        /// The mailbox is in use (open) or answered already (answer).
        case taken
        case rateLimited
        /// The space holds the most items it may.
        case full
        case wrongTag
    }

    public struct Item: Decodable, Sendable {
        public var kind: String
        public var id: String
        public var change: Int
        public var data: Data?
        public var deleted: Bool?
    }

    public struct Page: Decodable, Sendable {
        public var items: [Item]
        public var change: Int
        public var more: Bool
    }

    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = productionURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Production, or `IPTV_CONTROL` (the dev deployment in tests).
    public static func live() -> ControlClient {
        if let text = ProcessInfo.processInfo.environment["IPTV_CONTROL"], let url = URL(string: text) {
            return ControlClient(baseURL: url)
        }
        return ControlClient()
    }

    // MARK: Items

    /// The items changed after `since`, all pages.
    public func items(_ key: ControlKey, since: Int) async throws -> (items: [Item], change: Int) {
        var all: [Item] = [], change = since
        while true {
            let page: Page = try await send("GET", "v1/items?since=\(change)", auth: key.authorization)
            all += page.items
            change = page.change
            if !page.more { return (all, change) }
        }
    }

    @discardableResult
    public func put<Value: Encodable>(_ value: Value, kind: ControlKind, id: String, key: ControlKey) async throws -> Int {
        let answer: Changed = try await send("PUT", "v1/items/\(kind.rawValue)/\(id)", auth: key.authorization,
                                             body: ItemBody(data: try key.seal(value, kind: kind, id: id)))
        return answer.change
    }

    public func delete(kind: ControlKind, id: String, key: ControlKey) async throws {
        let _: Changed = try await send("DELETE", "v1/items/\(kind.rawValue)/\(id)", auth: key.authorization)
    }

    public func deleteSpace(_ key: ControlKey) async throws {
        let _: Empty = try await send("DELETE", "v1/space", auth: key.authorization)
    }

    // MARK: Pairing

    /// The server opens its mailbox; `.taken` means another server uses this code right now.
    public func openMailbox(_ code: PairingCode, publicKey: Data, tag: Data, claim: Data) async throws {
        struct Body: Encodable { var publicKey: Data; var tag: Data; var claimHash: String }
        struct Answer: Decodable { var expiresAt: String }
        let hash = sha256Hex(Data(claim.base64URL.utf8))
        let _: Answer = try await send("POST", "v1/pairing/\(code.mailbox)", body: Body(publicKey: publicKey, tag: tag, claimHash: hash))
    }

    /// The app reads the server's key; `.notFound` for an unknown or expired code.
    public func mailbox(_ code: PairingCode) async throws -> (publicKey: Data, tag: Data) {
        struct Answer: Decodable { var publicKey: Data; var tag: Data }
        let answer: Answer = try await send("GET", "v1/pairing/\(code.mailbox)")
        return (answer.publicKey, answer.tag)
    }

    public func answer(_ code: PairingCode, message: Data, tag: Data) async throws {
        struct Body: Encodable { var message: Data; var tag: Data }
        let _: Empty = try await send("PUT", "v1/pairing/\(code.mailbox)/message", body: Body(message: message, tag: tag))
    }

    /// The server's poll: nil until the app answered; taking the message closes the mailbox.
    public func pickUp(_ code: PairingCode, claim: Data) async throws -> (message: Data, tag: Data)? {
        struct Answer: Decodable { var message: Data?; var tag: Data? }
        let answer: Answer = try await send("GET", "v1/pairing/\(code.mailbox)/message", auth: "Claim \(claim.base64URL)")
        guard let message = answer.message, let tag = answer.tag else { return nil }
        return (message, tag)
    }

    public func closeMailbox(_ code: PairingCode, claim: Data) async throws {
        let _: Empty = try await send("DELETE", "v1/pairing/\(code.mailbox)", auth: "Claim \(claim.base64URL)")
    }

    // MARK: Transport

    private struct Empty: Decodable {}
    private struct ItemBody: Encodable { var data: Data }
    private struct Changed: Decodable { var change: Int }
    private struct Refusal: Decodable { var error: String }

    private func send<Answer: Decodable>(_ method: String, _ path: String, auth: String? = nil) async throws -> Answer {
        try await send(method, path, auth: auth, body: Optional<Data>.none)
    }

    private func send<Body: Encodable, Answer: Decodable>(_ method: String, _ path: String, auth: String? = nil, body: Body?) async throws -> Answer {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)!)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let auth { request.setValue(auth, forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let code = (try? JSONDecoder().decode(Refusal.self, from: data))?.error ?? ""
            switch (status, code) {
            case (404, _): throw Failure.notFound
            case (409, _): throw Failure.taken
            case (429, _): throw Failure.rateLimited
            case (413, "full"): throw Failure.full
            default: throw Failure.server(status: status, code: code)
            }
        }
        if data.isEmpty, let empty = Empty() as? Answer { return empty }
        return try JSONDecoder().decode(Answer.self, from: data)
    }
}
