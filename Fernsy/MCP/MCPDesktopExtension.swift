import AppKit

/// "Zu Claude Desktop hinzufügen …": a desktop extension (`.mcpb`, manifest 0.3) that Claude
/// Desktop installs with one click. It holds a tiny stdio bridge that forwards MCP messages to
/// Fernsy's local endpoint with the access token, on the Node.js bundled with Claude Desktop.
@MainActor
enum MCPDesktopExtension {
    static let claudeBundleID = "com.anthropic.claudefordesktop"

    /// Builds `Fernsy.mcpb` in the temporary directory.
    static func build(token: String) throws -> URL {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("mcpb", isDirectory: true)
        try? fm.removeItem(at: base)
        let folder = base.appendingPathComponent("Fernsy", isDirectory: true)
        try fm.createDirectory(at: folder.appendingPathComponent("server"), withIntermediateDirectories: true)
        let icon = iconPNG()
        if let icon { try icon.write(to: folder.appendingPathComponent("icon.png")) }
        try manifest(token: token, icon: icon != nil).write(to: folder.appendingPathComponent("manifest.json"))
        try Data(bridge.utf8).write(to: folder.appendingPathComponent("server/index.js"))

        // The manifest must sit at the archive's root: ditto zips the folder's contents (without
        // the folder itself, unlike NSFileCoordinator's .forUploading).
        let zipped = base.appendingPathComponent("Fernsy.mcpb")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--norsrc", folder.path, zipped.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        try? fm.removeItem(at: folder)
        AppLog.info(.mcp, "desktop extension built")
        return zipped
    }

    /// Removes a bundle left from earlier: it contains the token.
    static func cleanUp() {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("mcpb"))
    }

    static var claudeApp: URL? {
        #if DEBUG
        // IPTV_TESTNOCLAUDE=1: behave as if Claude Desktop were not installed.
        if ProcessInfo.processInfo.environment["IPTV_TESTNOCLAUDE"] == "1" { return nil }
        #endif
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeBundleID)
    }

    /// Hands the bundle to Claude Desktop, or lets the user save it when Claude is missing.
    static func addToClaude(token: String) {
        let bundle: URL
        do {
            bundle = try build(token: token)
        } catch {
            AppLog.error(.mcp, "desktop extension failed: \(error.localizedDescription)")
            return
        }
        if let claude = claudeApp {
            AppLog.info(.mcp, "opening the desktop extension in Claude Desktop")
            NSWorkspace.shared.open([bundle], withApplicationAt: claude, configuration: NSWorkspace.OpenConfiguration())
            // The install dialog has read it by then; the file holds the token.
            DispatchQueue.main.asyncAfter(deadline: .now() + 600) { cleanUp() }
            return
        }
        AppLog.info(.mcp, "Claude Desktop not found: saving the desktop extension")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Fernsy.mcpb"
        panel.message = String(localized: "Claude Desktop wurde nicht gefunden. Sichere die Erweiterung und öffne sie später mit Claude Desktop.")
        panel.begin { response in
            if response == .OK, let target = panel.url {
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.copyItem(at: bundle, to: target)
            }
            cleanUp()
        }
    }

    // MARK: Contents

    static func manifest(token: String, icon: Bool) throws -> Data {
        var manifest: [String: Any] = [
            "manifest_version": "0.3",
            "name": "fernsy",
            "display_name": "Fernsy",
            "version": semanticVersion,
            "description": "Your IPTV and Jellyfin player on this Mac: program guide, recently watched, recordings and playback.",
            "author": ["name": "mobilistics GmbH", "url": "https://www.fernsy.app"],
            "homepage": "https://www.fernsy.app",
            "server": [
                "type": "node",
                "entry_point": "server/index.js",
                "mcp_config": [
                    "command": "node",
                    "args": ["${__dirname}/server/index.js"],
                    // The token goes in directly: Claude Desktop does not apply the default of a
                    // sensitive user_config field and then never starts the server.
                    "env": ["FERNSY_ENDPOINT": MCPServer.endpoint, "FERNSY_TOKEN": token],
                ],
            ],
            "tools": MCPTools.definitions.map { ["name": $0["name"] ?? "", "description": $0["description"] ?? ""] },
            "compatibility": ["platforms": ["darwin"], "runtimes": ["node": ">=18.0.0"]],
        ]
        if icon { manifest["icon"] = "icon.png" }
        return try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// The manifest needs x.y.z: the app version padded, or 0.0.<build> for nightlies
    /// ("nightly-2026-10-25") and other non-numeric versions.
    static var semanticVersion: String {
        let info = Bundle.main.infoDictionary
        var version = info?["CFBundleShortVersionString"] as? String ?? ""
        #if DEBUG
        // IPTV_MCPVERSION=<version>: pretend the app has this version (e.g. a nightly's).
        if let fake = ProcessInfo.processInfo.environment["IPTV_MCPVERSION"] { version = fake }
        #endif
        let parts = version.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && Int($0) != nil }) {
            return (parts.map { String(Int($0)!) } + Array(repeating: "0", count: 3 - parts.count)).joined(separator: ".")
        }
        let build = (info?["CFBundleVersion"] as? String).flatMap { Int($0) } ?? 0
        return "0.0.\(build)"
    }

    private static func iconPNG() -> Data? {
        guard let icon = NSApp?.applicationIconImage,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// The extension's server: newline-delimited JSON-RPC on stdin, one POST per message to
    /// Fernsy, answers on stdout in order. No dependencies (Node's own fetch).
    static let bridge = #"""
    // Fernsy desktop extension: forwards MCP messages from Claude Desktop to Fernsy's local server.
    const endpoint = process.env.FERNSY_ENDPOINT;
    const token = process.env.FERNSY_TOKEN || "";
    const NOT_RUNNING = "Fernsy is not running, or its MCP server is off. Open Fernsy and switch on Settings › Assistants › MCP Server.";
    const BAD_TOKEN = "Fernsy refused the access token. It was probably renewed in Fernsy: add Fernsy to Claude Desktop again (Settings › Assistants) or paste the new token in this extension's settings.";

    function write(message) { process.stdout.write(JSON.stringify(message) + "\n"); }

    function failure(message, text) {
      if (message.id === undefined || message.id === null) return;
      if (message.method === "tools/call") {
        write({ jsonrpc: "2.0", id: message.id, result: { content: [{ type: "text", text }], isError: true } });
      } else {
        write({ jsonrpc: "2.0", id: message.id, error: { code: -32000, message: text } });
      }
    }

    async function forward(line) {
      let message;
      try { message = JSON.parse(line); } catch { return; }
      let response;
      try {
        response = await fetch(endpoint, {
          method: "POST",
          headers: { "Content-Type": "application/json", "Accept": "application/json", "Authorization": "Bearer " + token },
          body: line,
        });
      } catch {
        return failure(message, NOT_RUNNING);
      }
      if (response.status === 401) return failure(message, BAD_TOKEN);
      if (response.status === 202) return;
      const text = await response.text();
      if (!response.ok || !text) return failure(message, "Fernsy answered HTTP " + response.status + ".");
      process.stdout.write(text.trim() + "\n");
    }

    let buffer = "";
    let queue = Promise.resolve();
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      buffer += chunk;
      let index;
      while ((index = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, index).trim();
        buffer = buffer.slice(index + 1);
        if (line) queue = queue.then(() => forward(line));
      }
    });
    process.stdin.on("end", () => { queue.then(() => process.exit(0)); });
    """#
}
