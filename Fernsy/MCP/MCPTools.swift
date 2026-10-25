import AppKit
import SwiftUI

/// The MCP tools: the guide, the viewing history, recordings and playback, through the same
/// functions and rules as the app's own views (hidden channels, adult content, stream limit).
@MainActor
final class MCPTools {
    struct ToolError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private unowned let app: AppModel
    private var actions: FernsyActions { FernsyActions(app: app) }

    init(app: AppModel) { self.app = app }

    static let instructions = """
        Fernsy is the user's IPTV and Jellyfin player on this Mac. Times are ISO 8601 in the Mac's \
        time zone. Find channel ids with find_channels; shows have a show_id ("<channel>:<start \
        epoch>") that schedule_recording takes. The guide is loaded per channel, so search_program \
        searches favourites and recently watched channels unless you pass channel_ids (at most 50). \
        Recordings follow the account's stream limit: a refused result explains why.
        """

    nonisolated static let channelLimit = FernsyActions.channelLimit

    // MARK: Definitions

    static let definitions: [[String: Any]] = [
        tool("find_channels", "Find live TV channels by name or category. Without arguments it lists the categories and the favourite channels.", [
            "query": ["type": "string", "description": "Part of the channel name"],
            "category": ["type": "string", "description": "Category name or id"],
            "favorites_only": ["type": "boolean"],
            "limit": ["type": "integer", "minimum": 1, "maximum": 200],
        ], readOnly: true),
        tool("whats_on", "The current and next show on the given channels (default: favourites, then recently watched).", [
            "channel_ids": ["type": "array", "items": ["type": "integer"], "maxItems": channelLimit],
        ], readOnly: true),
        tool("get_program", "A channel's program guide for a time range (default: the next 24 hours).", [
            "channel_id": ["type": "integer"],
            "from": ["type": "string", "format": "date-time"],
            "to": ["type": "string", "format": "date-time"],
        ], required: ["channel_id"], readOnly: true),
        tool("search_program", "Search show titles and descriptions in the guide of up to 50 channels (default: favourites and recently watched).", [
            "query": ["type": "string"],
            "channel_ids": ["type": "array", "items": ["type": "integer"], "maxItems": channelLimit],
            "from": ["type": "string", "format": "date-time"],
            "to": ["type": "string", "format": "date-time"],
        ], required: ["query"], readOnly: true),
        tool("recently_watched", "Recently watched live channels, IPTV films in progress, and Jellyfin Continue Watching and Next Up.", [:], readOnly: true),
        tool("list_recordings", "Running, scheduled and finished recordings.", [
            "status": ["type": "string", "enum": ["all", "scheduled", "recording", "done", "failed"]],
        ], readOnly: true),
        tool("schedule_recording", "Schedule a recording of a show from the guide, with the app's padding and stream-limit rules.", [
            "show_id": ["type": "string", "description": "From get_program, whats_on or search_program"],
            "channel_id": ["type": "integer", "description": "With start, instead of show_id"],
            "start": ["type": "string", "format": "date-time"],
        ], readOnly: false),
        tool("cancel_recording", "Remove a scheduled recording. Running and finished recordings and their files are not touched.", [
            "recording_id": ["type": "string"],
        ], required: ["recording_id"], readOnly: false),
        tool("play", "Play an item in Fernsy's player: live:<channel id> (switches channels), movie:<id>, episode:<series id>:<episode id>, jellyfin:<item id> or recording:<id>. Never ends a running recording.", [
            "item_id": ["type": "string"],
        ], required: ["item_id"], readOnly: false),
        tool("now_playing", "What Fernsy's player plays right now.", [:], readOnly: true),
        tool("stop_playback", "Stop playback and close the player.", [:], readOnly: false),
    ]

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String] = [], readOnly: Bool) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": description, "inputSchema": schema,
                "annotations": ["readOnlyHint": readOnly, "destructiveHint": false, "openWorldHint": false]]
    }

    // MARK: Calls

    func call(_ name: String, _ args: [String: Any]) async throws -> [String: Any] {
        switch name {
        case "find_channels": return findChannels(args)
        case "whats_on": return try await whatsOn(args)
        case "get_program": return try await program(args)
        case "search_program": return try await searchProgram(args)
        case "recently_watched": return recentlyWatched()
        case "list_recordings": return listRecordings(args)
        case "schedule_recording": return try await scheduleRecording(args)
        case "cancel_recording": return try cancelRecording(args)
        case "play": return try await play(args)
        case "now_playing": return nowPlaying()
        case "stop_playback": return stopPlayback()
        default: throw ToolError("Unknown tool \(name)")
        }
    }

    // MARK: Channels and guide

    private var visibleChannels: [LiveChannel] { actions.visibleChannels }

    private func visibleChannel(_ id: Int) throws -> LiveChannel {
        guard let channel = actions.visibleChannel(id) else { throw ToolError("No visible channel with id \(id)") }
        return channel
    }

    private func findChannels(_ args: [String: Any]) -> [String: Any] {
        let query = args["query"] as? String ?? ""
        let category = (args["category"] as? String).flatMap { name in
            app.visibleCategories(app.liveCategories).first { $0.id == name || makeSearchKey($0.displayName) == makeSearchKey(name) || makeSearchKey($0.name) == makeSearchKey(name) }
        }
        let limit = min(200, max(1, args["limit"] as? Int ?? 50))
        var list = app.filteredChannels(categoryID: category?.id ?? allCategoryID, query: query)
        if args["favorites_only"] as? Bool == true { list = list.filter { app.isFavorite("live:\($0.id)") } }
        var result: [String: Any] = [:]
        if query.isEmpty && category == nil && args["favorites_only"] == nil {
            let counts = Dictionary(grouping: visibleChannels) { $0.categoryId ?? "" }.mapValues(\.count)
            result["categories"] = app.visibleCategories(app.liveCategories).filter { !app.isCategoryHidden($0.id) }
                .map { ["id": $0.id, "name": $0.displayName, "channels": counts[$0.id] ?? 0] }
            list = list.filter { app.isFavorite("live:\($0.id)") }
            result["note"] = "Without arguments only favourite channels are listed."
        } else if let name = args["category"] as? String, category == nil {
            result["note"] = "No category named \(name); searched all channels."
        }
        result["total"] = list.count
        result["channels"] = list.prefix(limit).map(channelJSON)
        return result
    }

    private func channelJSON(_ channel: LiveChannel) -> [String: Any] {
        var value: [String: Any] = ["id": channel.id, "name": channel.displayName, "favorite": app.isFavorite("live:\(channel.id)")]
        if let category = app.liveCategories.first(where: { $0.id == channel.categoryId }) { value["category"] = category.displayName }
        return value
    }

    private func loadGuides(_ ids: [Int], timeout: TimeInterval = 20) async { await actions.loadGuides(ids, timeout: timeout) }

    private func entries(_ channelId: Int) -> [EPGEntry] { actions.entries(channelId) }

    private func showJSON(_ entry: EPGEntry, on channel: LiveChannel) -> [String: Any] {
        var value: [String: Any] = [
            "show_id": "\(channel.id):\(Int(entry.start.timeIntervalSince1970))",
            "channel_id": channel.id, "channel": channel.displayName, "title": entry.title,
            "start": Self.iso(entry.start), "end": Self.iso(entry.end),
        ]
        if !entry.description.isEmpty { value["description"] = String(entry.description.prefix(300)) }
        if let recording = app.recorder.recordings.first(where: { $0.matches(channelId: channel.id, entry: entry) && $0.status != .skipped }) {
            value["recording"] = ["recording_id": recording.id.uuidString, "status": recording.status.rawValue]
        }
        return value
    }

    /// Given ids (visible ones), or favourites plus recently watched.
    private func scope(_ args: [String: Any]) throws -> [LiveChannel] {
        if let ids = args["channel_ids"] as? [Int], !ids.isEmpty {
            let visible = Dictionary(uniqueKeysWithValues: visibleChannels.map { ($0.id, $0) })
            return Array(ids.compactMap { visible[$0] }.prefix(Self.channelLimit))
        }
        let list = actions.favoritesAndRecent()
        guard !list.isEmpty else { throw ToolError("No favourite or recently watched channels; pass channel_ids (see find_channels).") }
        return list
    }

    private func whatsOn(_ args: [String: Any]) async throws -> [String: Any] {
        let channels = try scope(args)
        await loadGuides(channels.map(\.id))
        return ["channels": channels.map { channel -> [String: Any] in
            let (current, next) = actions.nowAndNext(channel.id)
            var value = channelJSON(channel)
            if let current { value["now"] = showJSON(current, on: channel) }
            if let next { value["next"] = showJSON(next, on: channel) }
            if current == nil && next == nil { value["note"] = "No program data" }
            return value
        }]
    }

    private func range(_ args: [String: Any]) throws -> (from: Date, to: Date) {
        let from = try (args["from"] as? String).map(Self.date) ?? Date()
        let to = try (args["to"] as? String).map(Self.date) ?? from.addingTimeInterval(24 * 3600)
        guard to > from else { throw ToolError("'to' must be after 'from'") }
        return (from, to)
    }

    private func program(_ args: [String: Any]) async throws -> [String: Any] {
        guard let id = args["channel_id"] as? Int else { throw ToolError("channel_id is required") }
        let channel = try visibleChannel(id)
        let (from, to) = try range(args)
        await loadGuides([id])
        let shows = entries(id).filter { $0.end > from && $0.start < to }.sorted { $0.start < $1.start }
        return ["channel": channelJSON(channel), "from": Self.iso(from), "to": Self.iso(to), "shows": shows.map { showJSON($0, on: channel) }]
    }

    private func searchProgram(_ args: [String: Any]) async throws -> [String: Any] {
        let query = args["query"] as? String ?? ""
        guard !makeSearchKey(query.trimmingCharacters(in: .whitespaces)).isEmpty else { throw ToolError("query is required") }
        let channels = try scope(args)
        let from = try (args["from"] as? String).map(Self.date) ?? Date()
        let to = try (args["to"] as? String).map(Self.date) ?? .distantFuture
        let hits = await actions.searchGuide(query, on: channels, from: from, to: to)
        return ["searched_channels": channels.map { ["id": $0.id, "name": $0.displayName] },
                "shows": hits.prefix(100).map { showJSON($0.entry, on: $0.channel) }]
    }

    // MARK: History

    private func recentlyWatched() -> [String: Any] {
        let now = Date()
        var result: [String: Any] = [
            "live": app.filteredChannels(categoryID: recentChannelsID, query: "").map { channel -> [String: Any] in
                var value = channelJSON(channel)
                if let current = entries(channel.id).first(where: { $0.start <= now && $0.end > now }) { value["now"] = current.title }
                return value
            },
        ]
        let adultMovies = Set(app.movieCategories.filter(app.isAdultCategory).map(\.id))
        result["iptv_films_in_progress"] = app.movies
            .filter { app.showAdult || (!$0.isAdult && !adultMovies.contains($0.categoryId ?? "")) }
            .compactMap { movie -> [String: Any]? in
                let position = app.resumePosition("movie.\(movie.id)")
                guard position > 0 else { return nil }
                var value: [String: Any] = ["item_id": "movie:\(movie.id)", "title": movie.name, "position_seconds": Int(position)]
                if let fraction = app.resumeFraction("movie.\(movie.id)") { value["progress_percent"] = Int(fraction * 100) }
                return value
            }
        if app.hasJellyfin {
            result["jellyfin"] = ["continue_watching": app.jellyfin.resume.map(jellyfinJSON), "next_up": app.jellyfin.nextUp.map(jellyfinJSON)]
        }
        return result
    }

    private func jellyfinJSON(_ item: JFItem) -> [String: Any] {
        var title = item.name
        if item.type == "Episode", let series = item.seriesName {
            let code = [item.parentIndexNumber.map { "S\($0)" }, item.indexNumber.map { "E\($0)" }].compactMap { $0 }.joined()
            title = "\(series) \(code) · \(item.name)"
        }
        var value: [String: Any] = ["item_id": "jellyfin:\(item.id)", "title": title, "type": item.type]
        if let percent = item.userData?.playedPercentage { value["progress_percent"] = Int(percent) }
        return value
    }

    // MARK: Recordings

    private func recordingJSON(_ recording: Recording) -> [String: Any] {
        var value: [String: Any] = [
            "recording_id": recording.id.uuidString, "channel_id": recording.channelId, "channel": recording.channelName,
            "title": recording.title, "status": recording.status.rawValue,
            "show_start": Self.iso(recording.start), "show_end": Self.iso(recording.end),
            "record_start": Self.iso(recording.recordStart), "record_end": Self.iso(recording.recordEnd),
        ]
        if let file = recording.fileName { value["file"] = file }
        if let error = recording.error { value["error"] = error }
        return value
    }

    private func listRecordings(_ args: [String: Any]) -> [String: Any] {
        let status = args["status"] as? String ?? "all"
        let list = app.recorder.recordings
            .filter { status == "all" || $0.status.rawValue == status }
            .sorted { $0.recordStart < $1.recordStart }
        return ["recordings": list.map(recordingJSON)]
    }

    private func scheduleRecording(_ args: [String: Any]) async throws -> [String: Any] {
        let channelId: Int, start: Date
        if let showId = args["show_id"] as? String {
            let parts = showId.split(separator: ":")
            guard parts.count == 2, let id = Int(parts[0]), let epoch = Double(parts[1]) else { throw ToolError("show_id must look like <channel>:<start epoch>") }
            (channelId, start) = (id, Date(timeIntervalSince1970: epoch))
        } else if let id = args["channel_id"] as? Int, let text = args["start"] as? String {
            (channelId, start) = (id, try Self.date(text))
        } else {
            throw ToolError("Pass show_id, or channel_id and start")
        }
        let channel = try visibleChannel(channelId)
        await loadGuides([channelId])
        guard let entry = entries(channelId).first(where: { abs($0.start.timeIntervalSince(start)) < 60 }) else {
            throw ToolError("No show on \(channel.displayName) starts at \(Self.iso(start)); check get_program.")
        }
        guard entry.end > Date() else { throw ToolError("„\(entry.title)“ has already ended.") }
        switch actions.schedule(entry, on: channel) {
        case .refused(let reason):
            return ["result": "refused", "reason": reason]
        case .planned(let recording, let notice):
            var value: [String: Any] = ["result": notice == nil ? "planned" : "planned_with_shortened_padding"]
            if let notice { value["notice"] = notice }
            if let recording { value["recording"] = recordingJSON(recording) }
            return value
        }
    }

    private func cancelRecording(_ args: [String: Any]) throws -> [String: Any] {
        guard let text = args["recording_id"] as? String, let id = UUID(uuidString: text),
              let recording = app.recorder.recordings.first(where: { $0.id == id }) else { throw ToolError("No recording with this id") }
        guard recording.status == .scheduled else {
            throw ToolError("Only scheduled recordings can be cancelled; „\(recording.title)“ is \(recording.status.rawValue). Its file is kept.")
        }
        app.recorder.stop(id)
        AppLog.info(.mcp, "cancelled \(recording.title)")
        return ["result": "cancelled", "recording_id": text]
    }

    // MARK: Playback

    private func play(_ args: [String: Any]) async throws -> [String: Any] {
        guard let itemId = args["item_id"] as? String else { throw ToolError("item_id is required") }
        let parts = itemId.split(separator: ":", maxSplits: 2).map(String.init)
        switch (parts.first, parts.count) {
        case ("live", 2):
            guard let id = Int(parts[1]) else { throw ToolError("Bad channel id") }
            let channel = try visibleChannel(id)
            if case .blocked(let first) = actions.playChannel(channel) {
                return ["result": "blocked",
                        "reason": "„\(first.title)“ is being recorded on \(first.channelName) and the account allows \(app.tuners.limit) stream(s). Playing \(channel.displayName) would end that recording; nothing was changed."]
            }
        case ("movie", 2):
            guard app.showsIPTVMovies, let id = Int(parts[1]), let movie = app.movies.first(where: { $0.id == id }) else { throw ToolError("No IPTV film with this id") }
            app.play(movie)
        case ("episode", 3):
            guard app.showsIPTVSeries, let seriesId = Int(parts[1]), let show = app.series.first(where: { $0.id == seriesId }),
                  let client = app.client else { throw ToolError("No IPTV series with this id") }
            let info = try await client.seriesInfo(seriesId)
            guard let episode = info.seasons.values.joined().first(where: { $0.id == parts[2] }) else { throw ToolError("No episode \(parts[2]) in \(show.name)") }
            app.play(episode, of: show)
        case ("jellyfin", 2):
            guard app.hasJellyfin else { throw ToolError("No Jellyfin account") }
            let item = try await app.jellyfin.call { try await $0.item(userId: $1, id: parts[1]) }
            app.play(jellyfin: item)
        case ("recording", 2):
            guard let id = UUID(uuidString: parts[1]), let recording = app.recorder.recordings.first(where: { $0.id == id }),
                  recording.fileName != nil else { throw ToolError("No recording with a file and this id") }
            app.play(recording)
        default:
            throw ToolError("item_id must be live:<id>, movie:<id>, episode:<series>:<episode>, jellyfin:<id> or recording:<id>")
        }
        PlayerWindow.show(app)
        AppLog.info(.mcp, "play \(itemId)")
        return ["result": "playing", "item_id": itemId]
    }

    private func nowPlaying() -> [String: Any] {
        guard let item = app.nowPlaying else { return ["playing": false] }
        var value: [String: Any] = ["playing": true, "title": item.title]
        if let subtitle = item.subtitle { value["subtitle"] = subtitle }
        switch item.kind {
        case .live(let id, _):
            value["item_id"] = "live:\(id)"
            if let channel = app.channel(id) {
                value["channel"] = channel.displayName
                if let current = entries(id).first(where: { $0.start <= Date() && $0.end > Date() }) { value["show"] = showJSON(current, on: channel) }
            }
        case .movie(let id): value["item_id"] = "movie:\(id)"
        case .episode(let id, let seriesId): value["item_id"] = "episode:\(seriesId):\(id)"
        case .recording(let id): value["item_id"] = "recording:\(id.uuidString)"
        case .jellyfin(let id, _, _): value["item_id"] = "jellyfin:\(id)"
        }
        return value
    }

    private func stopPlayback() -> [String: Any] {
        guard actions.stopPlayback() else { return ["result": "nothing_playing"] }
        AppLog.info(.mcp, "stopped playback")
        return ["result": "stopped"]
    }

    // MARK: Dates

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter
    }()

    static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

    static func date(_ text: String) throws -> Date {
        if let date = isoFormatter.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        // Without an offset: the Mac's time zone.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: text) { return date }
        }
        throw ToolError("Not an ISO 8601 date: \(text)")
    }
}

/// Opens the player window from outside a view (an MCP `play` while no library window is
/// open, e.g. Fernsy runs in the menu bar). Views hand over their `openWindow`.
@MainActor
enum PlayerWindow {
    static var openWindow: OpenWindowAction?
    /// From the menu bar item, which outlives the windows (see `MenuBarLabel`).
    static var menuBarOpenWindow: OpenWindowAction?

    private static func open(_ id: String) {
        (menuBarOpenWindow ?? openWindow)?(id: id)
    }

    private static var window: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("player") == true }
    }

    static func show(_ app: AppModel) {
        guard !app.isPictureInPictureActive, window?.isVisible != true else { return }
        NSApp.setActivationPolicy(.regular)
        open("player")
    }

    static func close() {
        if let window, window.isVisible { window.close() }
    }

    /// Brings the library window to the front, or opens one (Fernsy may run in the menu bar).
    static func showLibrary() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if let library = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("library") == true && $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized) }) {
            library.deminiaturize(nil)
            library.makeKeyAndOrderFront(nil)
            AppLog.detail(.app, "library window brought to the front")
        } else {
            AppLog.detail(.app, "opening a library window (menu bar action: \(menuBarOpenWindow != nil))")
            open("library")
        }
    }
}
