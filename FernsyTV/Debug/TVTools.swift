#if DEBUG
import FernsyCore
import FernsyPlayer
import Foundation

/// Debug MCP server of the Apple TV app (DEBUG only, IPTV_MCP=1, token IPTV_MCPTOKEN): a few
/// tools to drive and inspect the app from the Mac while it runs in the tvOS simulator, which
/// shares the Mac's network. Release builds have no listener.
@MainActor
final class TVDebugServer {
    static let port: UInt16 = 52325
    private var http: MCPHTTPServer?
    private var dispatcher: MCPDispatcher?

    func startIfRequested(model: TVModel) {
        let env = ProcessInfo.processInfo.environment
        guard env["IPTV_MCP"] == "1", let token = env["IPTV_MCPTOKEN"], http == nil else { return }
        let tools = TVTools(model: model)
        let dispatcher = MCPDispatcher(serverName: "Fernsy TV (debug)", instructions: TVTools.instructions,
                                       definitions: TVTools.definitions, imageKey: TVTools.imageKey) { name, arguments in
            try await tools.call(name, arguments)
        }
        self.dispatcher = dispatcher
        let server = MCPHTTPServer(port: Self.port, token: { token }, onState: { state in
            if case .running = state { AppLog.info(.mcp, "listening on http://127.0.0.1:\(TVDebugServer.port)/mcp") }
            if case .failed(let message) = state { AppLog.error(.mcp, "server failed: \(message)") }
        }, handler: { body in
            await dispatcher.handle(body)
        })
        http = server
        server.start()
    }
}

@MainActor
struct TVTools {
    let model: TVModel

    struct ToolError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    static let imageKey = "_image"
    static let instructions = "Debug tools of Fernsy on Apple TV (simulator): play a live channel, seek, read the player’s state and log, take a snapshot of the picture, record and list recordings."

    static let definitions: [[String: Any]] = [
        tool("play", "Play a live channel: item_id live:<channel id>.", ["item_id": ["type": "string"]], required: ["item_id"]),
        tool("stop_playback", "Stop playback and close the player.", [:]),
        tool("seek", "Seek in the live buffer. Pass one of by_seconds (negative = back) or to_live.",
             ["by_seconds": ["type": "number"], "to_live": ["type": "boolean"]]),
        tool("now_playing", "What plays: channel, state, live or how far behind, the buffer.", [:]),
        tool("playback_diagnostics", "now_playing plus the player's statistics and recent warnings.", [:]),
        tool("snapshot", "The picture shown now, as a JPEG.", [:]),
        tool("get_log", "The app log of this run: minimum level (detail, info, warning, error), optional query.",
             ["level": ["type": "string"], "query": ["type": "string"], "limit": ["type": "integer"]]),
        tool("record", "Record a live channel: the show on now (channel_id), or a later show (channel_id and start, ISO 8601, of a show in its guide).",
             ["channel_id": ["type": "integer"], "start": ["type": "string"]], required: ["channel_id"]),
        tool("list_recordings", "The recordings on this Apple TV: running, scheduled, finished, failed and missed, with file size.", [:]),
        tool("cancel_recording", "Stop a running recording (keeps what was recorded) or drop a scheduled one; delete: true also removes a finished one and its file.",
             ["recording_id": ["type": "string"], "delete": ["type": "boolean"]], required: ["recording_id"]),
    ]

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String] = []) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false]]
    }

    func call(_ name: String, _ args: [String: Any]) async throws -> [String: Any] {
        switch name {
        case "play":
            guard let item = args["item_id"] as? String, item.hasPrefix("live:"), let id = Int(item.dropFirst(5)) else {
                throw ToolError("item_id must look like live:<channel id>")
            }
            guard let channel = model.channels.first(where: { $0.id == id }) else { throw ToolError("No channel \(id)") }
            model.play(channel)
            return ["item_id": item, "result": "playing"]
        case "stop_playback":
            model.stop()
            return ["result": "stopped"]
        case "seek":
            guard model.playing != nil else { throw ToolError("Nothing is playing") }
            if args["to_live"] as? Bool == true { model.goLive() } else if let by = (args["by_seconds"] as? NSNumber)?.doubleValue {
                model.skip(by: by)
            } else { throw ToolError("Pass by_seconds or to_live") }
            try? await Task.sleep(for: .milliseconds(300))
            return nowPlaying()
        case "now_playing":
            return nowPlaying()
        case "playback_diagnostics":
            return diagnostics()
        case "snapshot":
            return try await snapshot()
        case "get_log":
            let levels: [String: LogLevel] = ["detail": .detail, "info": .info, "warning": .warning, "error": .error]
            let result = AppLog.shared.query(minimum: levels[args["level"] as? String ?? "info"] ?? .info,
                                             query: args["query"] as? String ?? "", limit: args["limit"] as? Int ?? 200)
            return ["entries": result.entries.map { $0.line }, "truncated": result.truncated]
        case "record":
            guard let id = args["channel_id"] as? Int, let channel = model.channels.first(where: { $0.id == id }) else {
                throw ToolError("Pass the channel_id of a live channel")
            }
            let message: String?
            if let start = (args["start"] as? String).flatMap({ try? Date($0, strategy: .iso8601) }) {
                await model.loadGuide(for: channel)
                guard let show = model.guide.guide(id).entries?.first(where: { abs($0.start.timeIntervalSince(start)) < 60 }) else {
                    throw ToolError("No show at \(start) on \(channel.displayName)")
                }
                message = model.schedule(show, on: channel)
            } else {
                message = model.recordNow(channel)
            }
            return ["result": "planned", "notice": message ?? "", "recordings": recordings()]
        case "list_recordings":
            return ["recordings": recordings()]
        case "cancel_recording":
            guard let value = args["recording_id"] as? String, let id = UUID(uuidString: value),
                  model.recorder.recordings.contains(where: { $0.id == id }) else { throw ToolError("No recording with that id") }
            if args["delete"] as? Bool == true { model.recorder.delete(id) } else { model.recorder.stop(id) }
            return ["recordings": recordings()]
        default:
            throw ToolError("Unknown tool \(name)")
        }
    }

    private func nowPlaying() -> [String: Any] {
        guard let channel = model.playing ?? model.previewing else { return ["playing": false] }
        let engine = model.engine, progress = engine.progress
        var value: [String: Any] = [
            "playing": true, "item_id": "live:\(channel.id)", "channel": channel.displayName,
            "preview": model.playing == nil, "muted": engine.isMuted,
            "state": "\(engine.status)", "follows_live": progress.followsLive,
            "buffer_seconds": Int(progress.liveEnd - progress.liveStart),
        ]
        if !progress.followsLive { value["behind_live_seconds"] = Int(max(0, progress.liveEnd - progress.position)) }
        if let show = model.currentShow(on: channel) { value["show"] = show.title }
        return value
    }

    private func recordings() -> [[String: Any]] {
        model.recorder.recordings.map { r in
            var value: [String: Any] = [
                "recording_id": r.id.uuidString, "title": r.title, "channel": r.channelName, "channel_id": r.channelId,
                "status": r.status.rawValue, "record_start": r.recordStart.ISO8601Format(), "record_end": r.recordEnd.ISO8601Format(),
            ]
            if let file = r.fileName { value["file"] = file }
            if let error = r.error { value["error"] = error }
            if let url = model.recorder.fileURL(r), let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                value["bytes"] = size
            }
            return value
        }
    }

    private func diagnostics() -> [String: Any] {
        var value = nowPlaying()
        let s = model.engine.stats
        value["stats"] = [
            "buffer_seconds": (s.bufferSeconds * 10).rounded() / 10, "bitrate_mbps": (s.bitrateMbps * 10).rounded() / 10,
            "dropped_frames": s.droppedFrames, "rebuffers": s.rebuffers, "seamless_reconnects": s.seamlessReconnects,
            "reconnecting": s.isReconnecting, "video_codec": s.videoCodec, "resolution": s.resolution,
            "decoder": s.decoder, "audio": s.audio,
        ] as [String: Any]
        let recent = AppLog.shared.query(minimum: .warning, since: Date().addingTimeInterval(-600), limit: 50)
        value["recent_warnings"] = recent.entries.map { $0.line }
        return value
    }

    private func snapshot() async throws -> [String: Any] {
        guard model.playing != nil, let shown = model.engine.lastPicture.value else {
            throw ToolError("No picture has been shown yet")
        }
        nonisolated(unsafe) let picture = shown
        let jpeg: Data? = await withCheckedContinuation { done in
            FrameGrabber.queue.async {
                done.resume(returning: StillImage.image(from: picture, maxWidth: 1280).flatMap { StillImage.jpeg($0, quality: 0.8) })
            }
        }
        guard let jpeg else { throw ToolError("The picture could not be converted") }
        var value = nowPlaying()
        value[Self.imageKey] = jpeg
        return value
    }
}
#endif
