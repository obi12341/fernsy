import Foundation
import Network

/// A minimal HTTP/1.1 server for the MCP endpoint: loopback only, one request per connection,
/// `POST /mcp` with a bearer token. Everything else is refused before the body is handled.
public final class MCPHTTPServer: @unchecked Sendable {
    public struct Response: Sendable {
        public var status: Int
        public var body: Data?
        public var headers: [String: String] = [:]

        public init(status: Int, body: Data? = nil, headers: [String: String] = [:]) {
            self.status = status
            self.body = body
            self.headers = headers
        }
    }

    /// Called on the main actor with the request body of an accepted `POST /mcp`.
    public typealias Handler = @MainActor (Data) async -> Response

    public enum State: Equatable { case starting, running, failed(String), stopped }

    public let port: UInt16
    private let token: @Sendable () -> String
    private let handler: Handler
    private let onState: @MainActor (State) -> Void
    private let queue = DispatchQueue(label: "de.mobilistics.fernsy.mcp")
    private var listener: NWListener?

    private static let maxHeader = 16 * 1024
    private static let maxBody = 1024 * 1024

    public init(port: UInt16, token: @escaping @Sendable () -> String, onState: @escaping @MainActor (State) -> Void, handler: @escaping Handler) {
        self.port = port
        self.token = token
        self.onState = onState
        self.handler = handler
    }

    public func start() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            report(.failed(error.localizedDescription))
            return
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.report(.running)
            case .failed(let error): self?.report(.failed(error.localizedDescription))
            case .cancelled: self?.report(.stopped)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        self.listener = listener
        report(.starting)
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func report(_ state: State) {
        Task { @MainActor in onState(state) }
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch Request.parse(buffer, maxHeader: Self.maxHeader, maxBody: Self.maxBody) {
            case .incomplete where !complete && error == nil:
                receive(connection, buffer: buffer)
            case .incomplete, .invalid:
                send(Response(status: 400, body: nil), on: connection)
            case .tooLarge:
                send(Response(status: 413, body: nil), on: connection)
            case .request(let request):
                respond(to: request, on: connection)
            }
        }
    }

    private func respond(to request: Request, on connection: NWConnection) {
        // Browsers send Origin; a website must never reach the server (DNS rebinding included).
        let host = request.headers["host"] ?? ""
        guard host == "127.0.0.1:\(port)" || host == "localhost:\(port)", request.headers["origin"] == nil else {
            return send(Response(status: 403, body: nil), on: connection)
        }
        guard request.path == "/mcp" || request.path.hasPrefix("/mcp?") else {
            return send(Response(status: 404, body: nil), on: connection)
        }
        guard Self.matches(request.headers["authorization"], token: token()) else {
            return send(Response(status: 401, body: nil, headers: ["WWW-Authenticate": "Bearer"]), on: connection)
        }
        guard request.method == "POST" else {
            return send(Response(status: 405, body: nil, headers: ["Allow": "POST"]), on: connection)
        }
        let body = request.body
        Task { @MainActor in
            let response = await self.handler(body)
            self.queue.async { self.send(response, on: connection) }
        }
    }

    /// Constant-time comparison of "Bearer <token>".
    private static func matches(_ header: String?, token: String) -> Bool {
        guard !token.isEmpty, let header, header.hasPrefix("Bearer ") else { return false }
        let given = Array(header.dropFirst(7).utf8), expected = Array(token.utf8)
        guard given.count == expected.count else { return false }
        return zip(given, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private func send(_ response: Response, on connection: NWConnection) {
        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        var headers = response.headers
        headers["Content-Length"] = String(response.body?.count ?? 0)
        headers["Connection"] = "close"
        if response.body != nil, headers["Content-Type"] == nil { headers["Content-Type"] = "application/json" }
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        var data = Data(head.utf8)
        if let body = response.body { data.append(body) }
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Payload Too Large"
        default: "Error"
        }
    }
}

/// One HTTP request, read in full (header plus `Content-Length` body).
private struct Request {
    let method: String
    let path: String
    /// Lower-cased names.
    let headers: [String: String]
    let body: Data

    enum Parse {
        case incomplete, invalid, tooLarge
        case request(Request)
    }

    static func parse(_ data: Data, maxHeader: Int, maxBody: Int) -> Parse {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeader ? .tooLarge : .incomplete
        }
        guard end.lowerBound <= maxHeader, let head = String(data: data[..<end.lowerBound], encoding: .utf8) else { return .invalid }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count == 3 else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .invalid }
        guard length <= maxBody else { return .tooLarge }
        let bodyStart = end.upperBound
        guard data.count - bodyStart >= length else { return .incomplete }
        return .request(Request(method: String(parts[0]), path: String(parts[1]), headers: headers,
                                body: data.subdata(in: bodyStart..<(bodyStart + length))))
    }
}
