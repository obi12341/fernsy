import Foundation

/// The JSON-RPC 2.0 side of an MCP server (tools only): initialize, ping, tools/list and
/// tools/call, answered as Streamable HTTP JSON responses for `MCPHTTPServer`. The app decides
/// which tools exist and runs them; a tool's result may carry a JPEG under `imageKey`, which
/// becomes an image content block.
@MainActor
public final class MCPDispatcher {
    public typealias Call = @MainActor (_ name: String, _ arguments: [String: Any]) async throws -> [String: Any]

    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    private let serverName: String
    private let instructions: String
    private let definitions: [[String: Any]]
    private let imageKey: String
    private let call: Call
    private var clientName = "?"

    public init(serverName: String, instructions: String, definitions: [[String: Any]], imageKey: String, call: @escaping Call) {
        self.serverName = serverName
        self.instructions = instructions
        self.definitions = definitions
        self.imageKey = imageKey
        self.call = call
    }

    public func handle(_ body: Data) async -> MCPHTTPServer.Response {
        guard let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              message["jsonrpc"] as? String == "2.0", let method = message["method"] as? String else {
            return reply(id: nil, error: (-32700, "Parse error: expected one JSON-RPC 2.0 message"))
        }
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]
        // Notifications (no id) get no answer.
        guard let id, !(id is NSNull) else { return MCPHTTPServer.Response(status: 202, body: nil) }

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            clientName = ((params["clientInfo"] as? [String: Any])?["name"] as? String) ?? "?"
            AppLog.info(.mcp, "client \(clientName) connected (protocol \(requested))")
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            return reply(id: id, result: [
                "protocolVersion": Self.protocolVersions.contains(requested) ? requested : Self.protocolVersions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": serverName, "title": serverName, "version": version],
                "instructions": instructions,
            ])
        case "ping":
            return reply(id: id, result: [:])
        case "tools/list":
            return reply(id: id, result: ["tools": definitions])
        case "tools/call":
            guard let name = params["name"] as? String else { return reply(id: id, error: (-32602, "Missing tool name")) }
            guard definitions.contains(where: { $0["name"] as? String == name }) else {
                return reply(id: id, error: (-32602, "Unknown tool: \(name)"))
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            AppLog.info(.mcp, "\(clientName): \(name)")
            let result: [String: Any]
            do {
                var value = try await call(name, arguments)
                var content: [[String: Any]] = []
                if let image = value.removeValue(forKey: imageKey) as? Data {
                    content.append(["type": "image", "mimeType": "image/jpeg", "data": image.base64EncodedString()])
                }
                content.append(["type": "text", "text": Self.text(value)])
                result = ["content": content, "structuredContent": value, "isError": false]
            } catch {
                AppLog.warning(.mcp, "\(name) failed: \(error.localizedDescription)")
                result = ["content": [["type": "text", "text": error.localizedDescription]], "isError": true]
            }
            return reply(id: id, result: result)
        default:
            return reply(id: id, error: (-32601, "Method not found: \(method)"))
        }
    }

    private static func text(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private func reply(id: Any?, result: [String: Any]? = nil, error: (code: Int, message: String)? = nil) -> MCPHTTPServer.Response {
        var message: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull()]
        if let error { message["error"] = ["code": error.code, "message": error.message] } else { message["result"] = result ?? [:] }
        let data = (try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes])) ?? Data()
        return MCPHTTPServer.Response(status: 200, body: data)
    }
}
