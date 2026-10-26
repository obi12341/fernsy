import FernsyCore
import Foundation
import Security

/// The local MCP server (Settings › Assistenten): JSON-RPC 2.0 over Streamable HTTP with JSON
/// responses, tools only. It runs while Fernsy runs and the setting is on.
@MainActor
final class MCPServer: ObservableObject {
    enum Status: Equatable { case off, starting, running, failed(String) }

    static let enabledKey = "mcp.enabled"
    #if DEBUG
    /// Debug builds use their own port, so they never collide with the installed app.
    static let port: UInt16 = 52324
    #else
    static let port: UInt16 = 52323
    #endif
    static var endpoint: String { "http://127.0.0.1:\(port)/mcp" }

    @Published private(set) var status: Status = .off
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            #if DEBUG
            if !inMemory { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
            #else
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            #endif
            AppLog.info(.mcp, "server \(isEnabled ? "on" : "off")")
            isEnabled ? start() : stop()
        }
    }
    @Published private(set) var token: String

    private let tokenBox = TokenBox()
    private var http: MCPHTTPServer?
    private let tools: MCPTools
    private let dispatcher: MCPDispatcher
    private var inMemory = false

    static let protocolVersions = MCPDispatcher.protocolVersions

    init(app: AppModel) {
        let tools = MCPTools(app: app)
        self.tools = tools
        dispatcher = MCPDispatcher(serverName: "Fernsy", instructions: MCPTools.instructions, definitions: MCPTools.definitions,
                                   imageKey: MCPTools.imageKey) { name, arguments in try await tools.call(name, arguments) }
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        token = ""
        #if DEBUG
        // Debug builds never touch the keychain: IPTV_MCP=1 switches the server on and
        // IPTV_MCPTOKEN sets the token, both in memory only.
        let env = ProcessInfo.processInfo.environment
        inMemory = true
        isEnabled = env["IPTV_MCP"] == "1"
        token = env["IPTV_MCPTOKEN"] ?? Self.newToken()
        #else
        if let stored = Keychain.load(String.self, account: "mcp.token") {
            token = stored
        } else {
            token = Self.newToken()
            Keychain.save(token, account: "mcp.token")
        }
        #endif
        tokenBox.value = token
        MCPDesktopExtension.cleanUp()
        if isEnabled { start() }
        #if DEBUG
        // IPTV_MCPBUNDLE=1: builds the desktop extension at launch and logs where (in the container).
        if env["IPTV_MCPBUNDLE"] == "1", let url = try? MCPDesktopExtension.build(token: token) {
            debugLog("[test] desktop extension at \(url.path)")
        }
        // IPTV_MCPADDCLAUDE=<s>: runs "Zu Claude Desktop hinzufügen …" after s seconds.
        if let delay = env["IPTV_MCPADDCLAUDE"].flatMap(Double.init) {
            let token = token
            Task {
                try? await Task.sleep(for: .seconds(delay))
                MCPDesktopExtension.addToClaude(token: token)
            }
        }
        // IPTV_MCPREGEN=<s>: creates a new token after s seconds, as the Settings button does.
        if let delay = env["IPTV_MCPREGEN"].flatMap(Double.init) {
            Task {
                try? await Task.sleep(for: .seconds(delay))
                regenerateToken()
            }
        }
        #endif
    }

    /// A new token; clients with the old one are refused from their next request on.
    func regenerateToken() {
        token = Self.newToken()
        tokenBox.value = token
        #if !DEBUG
        Keychain.save(token, account: "mcp.token")
        #endif
        AppLog.info(.mcp, "new access token")
    }

    private static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private func start() {
        guard http == nil else { return }
        let box = tokenBox
        let server = MCPHTTPServer(port: Self.port, token: { box.value }, onState: { [weak self] state in
            self?.httpStateChanged(state)
        }, handler: { [weak self] body in
            await self?.handle(body) ?? MCPHTTPServer.Response(status: 503, body: nil)
        })
        http = server
        server.start()
    }

    private func stop() {
        http?.stop()
        http = nil
        status = .off
    }

    private func httpStateChanged(_ state: MCPHTTPServer.State) {
        guard http != nil else { return }
        switch state {
        case .starting: status = .starting
        case .running:
            status = .running
            AppLog.info(.mcp, "listening on \(Self.endpoint)")
        case .failed(let message):
            status = .failed(message)
            AppLog.error(.mcp, "server failed: \(message)")
            http?.stop()
            http = nil
        case .stopped: break
        }
    }

    // MARK: JSON-RPC (FernsyCore's MCPDispatcher)

    private func handle(_ body: Data) async -> MCPHTTPServer.Response {
        await dispatcher.handle(body)
    }
}

/// The current token for the listener's queue.
private final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = ""
    var value: String {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
