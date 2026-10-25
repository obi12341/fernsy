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
        Recordings follow the account's stream limit: a refused result explains why. After a \
        Jellyfin episode ends, now_playing names the next one and when it starts by itself; \
        item_info and list_episodes give episode ids to play. To find a scene: get_subtitles when \
        it is described by what is said (Jellyfin), otherwise frames coarse to fine, then seek, and \
        snapshot to confirm.
        """

    nonisolated static let channelLimit = FernsyActions.channelLimit
    /// A handler's JPEG under this key becomes an image part of the result (see MCPServer).
    nonisolated static let imageKey = "_image"

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
        tool("now_playing", "What Fernsy's player plays right now, with position, duration, remaining time, end time and paused state; for live TV how far behind live and the current show.", [:], readOnly: true),
        tool("item_info", "Details of a film, episode, Jellyfin item or recording: title, runtime, remaining time, plot, year, series/season/episode, and for Jellyfin episodes the previous and next episode.", [
            "item_id": ["type": "string", "description": "movie:<id>, episode:<series id>:<episode id>, jellyfin:<item id> or recording:<id>"],
        ], required: ["item_id"], readOnly: true),
        tool("list_episodes", "Seasons of a Jellyfin series, or the episodes of one season with item ids, runtime and watched state.", [
            "series_id": ["type": "string", "description": "jellyfin:<series id>, or an episode's jellyfin:<item id>"],
            "season": ["type": "integer", "description": "Season number (0 = specials); without it the seasons are listed"],
        ], required: ["series_id"], readOnly: true),
        tool("stop_playback", "Stop playback and close the player.", [:], readOnly: false),
        tool("pause", "Pause what plays (live TV keeps receiving and continues behind live).", [:], readOnly: false),
        tool("resume", "Resume paused playback.", [:], readOnly: false),
        tool("seek", "Seek in what plays. Pass exactly one target. Live TV can only be rewound within its buffer (see now_playing's rewind fields).", [
            "by_seconds": ["type": "number", "description": "Relative jump, negative = back"],
            "to_position": ["type": "string", "description": "Seconds or h:mm:ss within a film, episode, Jellyfin item or recording"],
            "to_time": ["type": "string", "format": "date-time", "description": "Clock time within the live buffer"],
            "to_show_start": ["type": "boolean", "description": "Start of the current live show, as far as the buffer reaches"],
            "to_live": ["type": "boolean", "description": "Back to the live edge"],
        ], readOnly: false),
        tool("snapshot", "The picture the player shows right now, as an image, with its position (live TV: clock time). Does not change playback.", [:], readOnly: true),
        tool("frames", "A contact sheet: evenly spaced stills of a time range in one image, each labelled with its position (live TV: clock time), plus the list of times. Does not touch the player. For finding a scene: a coarse sheet first, then a finer one around the match, then seek. Works for Jellyfin items, recordings and the timeshift buffer of a playing or recording live channel; not for IPTV films and episodes.", [
            "item_id": ["type": "string", "description": "jellyfin:<id>, recording:<id> or live:<channel id>; default: what plays"],
            "from": ["type": "string", "description": "Seconds or h:mm:ss (live: ISO clock time); default: the start"],
            "to": ["type": "string", "description": "Seconds or h:mm:ss (live: ISO clock time); default: the end"],
            "count": ["type": "integer", "minimum": 4, "maximum": 48, "description": "Number of stills (default 24)"],
        ], readOnly: true),
        tool("get_subtitles", "The text subtitles of a Jellyfin item with start and end times, for finding a scene by what is said. Lists the text subtitle tracks and names the one returned.", [
            "item_id": ["type": "string", "description": "jellyfin:<id>; default: the Jellyfin item that plays"],
            "language": ["type": "string", "description": "Language code (e.g. ger, eng) or part of the track title"],
            "from": ["type": "string", "description": "Seconds or h:mm:ss"],
            "to": ["type": "string", "description": "Seconds or h:mm:ss"],
        ], readOnly: true),
        tool("get_log", "Fernsy's event log (redacted: no credentials or tokens), oldest first. Use it to explain errors, stutter, reconnects or failed recordings.", [
            "level": ["type": "string", "enum": ["error", "warning", "info", "detail"], "description": "Minimum level (default info)"],
            "category": ["type": "string", "enum": LogCategory.allCases.map(\.rawValue)],
            "minutes": ["type": "integer", "minimum": 1, "description": "Only the last N minutes of the current run (default 30)"],
            "query": ["type": "string", "description": "Text the message must contain"],
            "limit": ["type": "integer", "minimum": 1, "maximum": 1000, "description": "Newest N matching entries (default 200)"],
            "run": ["type": "string", "enum": ["current", "previous"]],
        ], readOnly: true),
        tool("playback_diagnostics", "Why playback stutters or fails: what plays, the player's state and statistics (buffer, bitrate, dropped frames, decode failures, rebuffers, reconnects with the last reason, codec, decoder) and recent player/network/tuner/timeshift warnings.", [:], readOnly: true),
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
        case "item_info": return try await itemInfo(args)
        case "list_episodes": return try await listEpisodes(args)
        case "snapshot": return try await snapshot()
        case "frames": return try await frames(args)
        case "get_subtitles": return try await subtitles(args)
        case "get_log": return getLog(args)
        case "pause": return try await setPaused(true)
        case "resume": return try await setPaused(false)
        case "seek": return try await seek(args)
        case "playback_diagnostics": return playbackDiagnostics()
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
                if let fraction = app.resumeFraction("movie.\(movie.id)") {
                    value["progress_percent"] = Int(fraction * 100)
                    value.merge(Self.runtime(duration: position / fraction, position: position)) { $1 }
                }
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
        value.merge(Self.runtime(duration: item.runTimeTicks.map { Double($0) / 10_000_000 },
                                 position: item.userData?.playbackPositionTicks.map { Double($0) / 10_000_000 })) { $1 }
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
        if let engine = app.playerEngine {
            let progress = engine.progress
            value["state"] = switch engine.status {
            case .playing: "playing"
            case .paused: "paused"
            case .buffering, .loading: "buffering"
            case .ended: "ended"
            case .idle: "idle"
            case .failed(let message): "failed: \(message)"
            }
            if engine.status == .ended, let playback = app.jellyfinPlayback, let next = playback.nextEpisode {
                var upcoming = neighbourJSON(next, prefix: "next").reduce(into: [String: Any]()) { $0[String($1.key.dropFirst(5))] = $1.value }
                if let at = playback.autoplayAt { upcoming["starts_in_seconds"] = max(0, Int(at.timeIntervalSinceNow.rounded(.up))) }
                else if playback.autoplayCancelled { upcoming["autoplay_cancelled"] = true }
                value["next"] = upcoming
            }
            if item.isLive {
                value["follows_live"] = progress.followsLive
                if !progress.followsLive { value["behind_live_seconds"] = Int(progress.behindLive) }
                value["timeshift"] = engine.isTimeshift
                if engine.isTimeshift {
                    let rewind = max(0, progress.position - progress.liveStart)
                    value["rewind_available_seconds"] = Int(rewind)
                    value["rewind_available"] = Self.clock(rewind)
                    value["buffer_seconds"] = Int(max(0, progress.liveEnd - progress.liveStart))
                    value["buffer_limit_minutes"] = UserDefaults.standard.integer(forKey: AppModel.timeshiftMinutesKey)
                    if let wall = engine.wallTime(of: progress.position) ?? progress.wallClock {
                        let bufferStart = engine.wallTime(of: progress.liveStart) ?? wall.addingTimeInterval(-rewind)
                        value["buffer_starts_at"] = Self.iso(bufferStart)
                        if case .live(let id, _) = item.kind, let show = entries(id).first(where: { $0.start <= wall && $0.end > wall }) {
                            value["show_start_in_buffer"] = show.start >= bufferStart
                        }
                    }
                }
            } else if progress.duration > 0 {
                value.merge(Self.timing(position: progress.position, duration: progress.duration, running: engine.status == .playing)) { $1 }
            } else {
                value["position_seconds"] = Int(progress.position)
                value["position"] = Self.clock(progress.position)
            }
        }
        return value
    }

    /// Position, duration and what is left, as seconds and h:mm:ss, plus the end time while it plays.
    static func timing(position: Double, duration: Double, running: Bool) -> [String: Any] {
        let remaining = max(0, duration - position)
        var value: [String: Any] = [
            "position_seconds": Int(position), "position": clock(position),
            "duration_seconds": Int(duration), "duration": clock(duration),
            "remaining_seconds": Int(remaining), "remaining": clock(remaining),
        ]
        if running { value["ends_at"] = iso(Date().addingTimeInterval(remaining)) }
        return value
    }

    /// Runtime and, once started, what is left.
    static func runtime(duration: Double?, position: Double?) -> [String: Any] {
        guard let duration, duration > 0 else { return [:] }
        var value: [String: Any] = ["runtime_seconds": Int(duration), "runtime": clock(duration)]
        if let position, position > 0 {
            value["position"] = clock(position)
            value["remaining_seconds"] = Int(max(0, duration - position))
            value["remaining"] = clock(max(0, duration - position))
        }
        return value
    }

    nonisolated static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }

    private func itemInfo(_ args: [String: Any]) async throws -> [String: Any] {
        guard let itemId = args["item_id"] as? String else { throw ToolError("item_id is required") }
        let parts = itemId.split(separator: ":", maxSplits: 2).map(String.init)
        var value: [String: Any] = ["item_id": itemId]
        switch (parts.first, parts.count) {
        case ("movie", 2):
            let adultMovies = Set(app.movieCategories.filter(app.isAdultCategory).map(\.id))
            guard app.showsIPTVMovies, let id = Int(parts[1]), let movie = app.movies.first(where: { $0.id == id }),
                  app.showAdult || (!movie.isAdult && !adultMovies.contains(movie.categoryId ?? "")) else { throw ToolError("No IPTV film with this id") }
            value["type"] = "film"
            value["title"] = movie.name
            let details = try? await app.client?.movieDetails(id)
            if let plot = details?.plot, !plot.isEmpty { value["plot"] = plot }
            if let genre = details?.genre { value["genre"] = genre }
            if let date = details?.releaseDate { value["release_date"] = date }
            let position = app.resumePosition("movie.\(id)")
            let duration = details?.duration.flatMap(Self.seconds) ?? app.resumeFraction("movie.\(id)").map { position / $0 }
            value.merge(Self.runtime(duration: duration, position: position)) { $1 }
        case ("episode", 3):
            guard app.showsIPTVSeries, let seriesId = Int(parts[1]), let show = app.series.first(where: { $0.id == seriesId }),
                  let client = app.client else { throw ToolError("No IPTV series with this id") }
            let info = try await client.seriesInfo(seriesId)
            guard let episode = info.seasons.values.joined().first(where: { $0.id == parts[2] }) else { throw ToolError("No episode \(parts[2]) in \(show.name)") }
            value["type"] = "episode"
            value["series"] = show.name
            value["season"] = episode.season
            value["episode"] = episode.number
            value["title"] = episode.title
            if let plot = episode.plot, !plot.isEmpty { value["plot"] = plot }
            value.merge(Self.runtime(duration: episode.durationSeconds.map(Double.init), position: app.resumePosition("episode.\(episode.id)"))) { $1 }
        case ("jellyfin", 2):
            guard app.hasJellyfin else { throw ToolError("No Jellyfin account") }
            let item = try await app.jellyfin.call { try await $0.item(userId: $1, id: parts[1]) }
            value.merge(jellyfinJSON(item)) { $1 }
            value["title"] = item.name
            if let series = item.seriesName { value["series"] = series }
            if let season = item.parentIndexNumber { value["season"] = season }
            if let episode = item.indexNumber { value["episode"] = episode }
            if let year = item.productionYear { value["year"] = year }
            if let plot = item.overview, !plot.isEmpty { value["plot"] = plot }
            if item.type == "Episode", let seriesId = item.seriesId {
                let episodes = try await seriesEpisodes(seriesId)
                // Specials only neighbour specials; regular episodes skip season 0.
                let isSpecial = item.parentIndexNumber == 0
                let run = episodes.filter { ($0.parentIndexNumber == 0) == isSpecial }
                if let index = run.firstIndex(where: { $0.id == item.id }) {
                    if index > 0 { value.merge(neighbourJSON(run[index - 1], prefix: "previous")) { $1 } }
                    if index + 1 < run.count { value.merge(neighbourJSON(run[index + 1], prefix: "next")) { $1 } }
                }
            }
        case ("recording", 2):
            guard let id = UUID(uuidString: parts[1]), let recording = app.recorder.recordings.first(where: { $0.id == id }) else {
                throw ToolError("No recording with this id")
            }
            value.merge(recordingJSON(recording)) { $1 }
            value["type"] = "recording"
            if !recording.description.isEmpty { value["plot"] = recording.description }
            value.merge(Self.runtime(duration: recording.recordEnd.timeIntervalSince(recording.recordStart),
                                     position: app.resumePosition("recording.\(id.uuidString)"))) { $1 }
        default:
            throw ToolError("item_id must be movie:<id>, episode:<series>:<episode>, jellyfin:<id> or recording:<id>")
        }
        return value
    }

    /// A series' episodes ordered by season and episode number.
    private func seriesEpisodes(_ seriesId: String) async throws -> [JFItem] {
        let episodes = try await app.jellyfin.call { try await $0.seriesEpisodes(userId: $1, seriesId: seriesId) }
        return episodes.sorted { ($0.parentIndexNumber ?? 0, $0.indexNumber ?? 0) < ($1.parentIndexNumber ?? 0, $1.indexNumber ?? 0) }
    }

    private func neighbourJSON(_ item: JFItem, prefix: String) -> [String: Any] {
        var value: [String: Any] = ["\(prefix)_item_id": "jellyfin:\(item.id)", "\(prefix)_title": item.name]
        if let season = item.parentIndexNumber { value["\(prefix)_season"] = season }
        if let episode = item.indexNumber { value["\(prefix)_episode"] = episode }
        return value
    }

    private func listEpisodes(_ args: [String: Any]) async throws -> [String: Any] {
        guard let raw = args["series_id"] as? String, !raw.isEmpty else { throw ToolError("series_id is required") }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 ? parts[0] == "jellyfin" : true else {
            throw ToolError("list_episodes is only available for Jellyfin series (jellyfin:<id>).")
        }
        guard app.hasJellyfin else { throw ToolError("No Jellyfin account") }
        let id = parts.last!
        let item = try await app.jellyfin.call { try await $0.item(userId: $1, id: id) }
        let seriesId: String
        switch item.type {
        case "Series": seriesId = item.id
        case "Episode", "Season": guard let series = item.seriesId else { fallthrough }; seriesId = series
        default: throw ToolError("\(item.name) is not a series or an episode")
        }
        let episodes = try await seriesEpisodes(seriesId)
        var value: [String: Any] = ["series_id": "jellyfin:\(seriesId)", "series": item.seriesName ?? item.name]
        if let season = (args["season"] as? NSNumber)?.intValue {
            let list = episodes.filter { $0.parentIndexNumber == season }
            guard !list.isEmpty else { throw ToolError("No season \(season) in \(item.seriesName ?? item.name)") }
            value["season"] = season
            value["episodes"] = list.map { episode -> [String: Any] in
                var entry = jellyfinJSON(episode)
                entry["title"] = episode.name
                if let number = episode.indexNumber { entry["episode"] = number }
                entry["played"] = episode.userData?.played ?? false
                return entry
            }
        } else {
            let seasons = Dictionary(grouping: episodes) { $0.parentIndexNumber ?? 0 }
            value["seasons"] = seasons.keys.sorted().map { number -> [String: Any] in
                let list = seasons[number] ?? []
                return ["season": number, "episodes": list.count, "played": list.filter { $0.userData?.played == true }.count]
            }
        }
        return value
    }

    // MARK: Scene search

    private func snapshot() async throws -> [String: Any] {
        let engine = try playingEngine()
        guard let shown = engine.lastPicture.value else { throw ToolError("No picture has been shown yet (still loading, or radio).") }
        nonisolated(unsafe) let picture = shown
        let progress = engine.progress
        let live = app.nowPlaying?.isLive == true
        var value = nowPlaying().filter { ["item_id", "title", "subtitle", "channel"].contains($0.key) }
        let jpeg: Data? = await withCheckedContinuation { done in
            FrameGrabber.queue.async {
                done.resume(returning: StillImage.image(from: picture, maxWidth: 1280).flatMap { StillImage.jpeg($0, quality: 0.8) })
            }
        }
        guard let jpeg else { throw ToolError("The picture could not be converted.") }
        if live {
            if let wall = engine.wallTime(of: progress.position) ?? progress.wallClock { value["time"] = Self.iso(wall) }
        } else {
            value["position_seconds"] = Int(progress.position)
            value["position"] = Self.clock(progress.position)
        }
        value[Self.imageKey] = jpeg
        return value
    }

    /// What `frames` reads: a byte source, how stream times become labels, and the default range.
    private struct FrameSource: @unchecked Sendable {
        let source: ByteSource
        let live: TimeshiftBuffer?
        let itemId: String
    }

    private func frameSource(_ itemId: String) async throws -> FrameSource {
        let parts = itemId.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count) {
        case ("live", 2):
            guard let id = Int(parts[1]), let tuner = app.tuners.tuner(id) else {
                throw ToolError("This channel has no buffer: frames reads only the timeshift buffer of a channel that plays or records.")
            }
            return FrameSource(source: BufferByteSource(buffer: tuner.buffer), live: tuner.buffer, itemId: itemId)
        case ("recording", 2):
            guard let id = UUID(uuidString: parts[1]), let recording = app.recorder.recordings.first(where: { $0.id == id }),
                  let url = app.recorder.fileURL(recording), FileManager.default.fileExists(atPath: url.path) else {
                throw ToolError("No recording with a file and this id")
            }
            return FrameSource(source: FileByteSource(url: url, isGrowing: { false }), live: nil, itemId: itemId)
        case ("jellyfin", 2):
            guard app.hasJellyfin else { throw ToolError("No Jellyfin account") }
            let item = try await app.jellyfin.call { try await $0.item(userId: $1, id: parts[1]) }
            guard let sourceId = item.mediaSources?.first?.id,
                  let url = try await app.jellyfin.call({ client, _ in client.directStreamURL(itemId: item.id, mediaSourceId: sourceId) }) else {
                throw ToolError("\(item.name) has no playable file")
            }
            return FrameSource(source: HTTPByteSource(url: url, isLive: false), live: nil, itemId: itemId)
        case ("movie", _), ("episode", _):
            throw ToolError("frames would need a second stream from the IPTV provider, which the account's stream limit does not allow. Use snapshot for the picture that plays.")
        default:
            throw ToolError("item_id must be jellyfin:<id>, recording:<id> or live:<channel id>")
        }
    }

    private func frames(_ args: [String: Any]) async throws -> [String: Any] {
        guard let itemId = (args["item_id"] as? String) ?? nowPlaying()["item_id"] as? String else {
            throw ToolError("Nothing is playing; pass item_id.")
        }
        let count = min(48, max(4, (args["count"] as? NSNumber)?.intValue ?? 24))
        let target = try await frameSource(itemId)
        let text = { (key: String) -> String? in (args[key] as? String) ?? (args[key] as? NSNumber)?.stringValue }
        var fromWall: Date?, toWall: Date?, fromPos: Double?, toPos: Double?
        if target.live != nil {
            fromWall = try text("from").map(Self.date)
            toWall = try text("to").map(Self.date)
        } else {
            fromPos = try text("from").map { try Self.position($0) }
            toPos = try text("to").map { try Self.position($0) }
        }
        let grabber = FrameGrabber(source: target.source, tileWidth: 320)
        // The whole sheet gets 60 s; what is there by then is returned.
        let deadline = Date().addingTimeInterval(60)
        let timer = DispatchWorkItem { grabber.cancel() }
        FrameGrabber.queue.asyncAfter(deadline: .now() + 60, execute: timer)
        defer { timer.cancel() }
        let result: (tiles: [(CGImage, String)], list: [[String: Any]], range: [String: Any]) = try await withCheckedThrowingContinuation { done in
            FrameGrabber.queue.async {
                do {
                    try grabber.open()
                    var tiles: [(CGImage, String)] = [], list: [[String: Any]] = [], range: [String: Any] = [:]
                    var seen = Set<Int64>()
                    func add(_ still: FrameGrabber.Still, label: String, entry: [String: Any]) {
                        tiles.append((still.image, label))
                        list.append(["index": list.count + 1].merging(entry) { $1 })
                    }
                    if let buffer = target.live, let source = target.source as? BufferByteSource {
                        guard let oldest = buffer.oldest, let newest = buffer.newest else { throw ToolError("The buffer is still empty.") }
                        let start = max(fromWall ?? oldest.wall, oldest.wall), end = min(toWall ?? newest.wall, newest.wall)
                        guard end > start else { throw ToolError("That time range is not in the buffer (\(Self.iso(oldest.wall)) to \(Self.iso(newest.wall))).") }
                        range = ["from": Self.iso(start), "to": Self.iso(end)]
                        let step = end.timeIntervalSince(start) / Double(count)
                        for i in 0..<count where Date() < deadline {
                            let wall = start.addingTimeInterval(step * (Double(i) + 0.5))
                            guard let entry = buffer.entry(atOrBeforeWall: wall), seen.insert(entry.offset).inserted,
                                  let still = grabber.still(atByte: source.position(ofBufferOffset: entry.offset)) else { continue }
                            let time = buffer.wallTime(of: still.streamTime - ffs_mux_delay()) ?? entry.wall
                            add(still, label: Self.clockTime(time), entry: ["time": Self.iso(time)])
                        }
                    } else {
                        let length = grabber.duration ?? 0
                        let start = max(0, fromPos ?? 0), end = min(toPos ?? length, length > 0 ? length : .infinity)
                        guard end.isFinite, end > start else { throw ToolError("The time range is empty or beyond the end (length \(Self.clock(length))).") }
                        range = ["from": Self.clock(start), "to": Self.clock(end), "length": Self.clock(length)]
                        let step = (end - start) / Double(count)
                        for i in 0..<count where Date() < deadline {
                            let position = start + step * (Double(i) + 0.5)
                            guard let still = grabber.still(atStreamTime: position + grabber.startTime) else { continue }
                            let shown = max(0, still.streamTime - grabber.startTime)
                            guard seen.insert(Int64(shown * 1000)).inserted else { continue }
                            add(still, label: Self.clock(shown), entry: ["position_seconds": Int(shown), "position": Self.clock(shown)])
                        }
                    }
                    grabber.close()
                    done.resume(returning: (tiles, list, range))
                } catch {
                    grabber.close()
                    done.resume(throwing: error)
                }
            }
        }
        guard !result.tiles.isEmpty else { throw ToolError("No picture could be decoded in that range.") }
        let jpeg: Data? = await withCheckedContinuation { done in
            FrameGrabber.queue.async {
                done.resume(returning: StillImage.contactSheet(result.tiles.map { (image: $0.0, label: $0.1) }).flatMap { StillImage.jpeg($0, quality: 0.7) })
            }
        }
        guard let jpeg else { throw ToolError("The contact sheet could not be created.") }
        var value: [String: Any] = ["item_id": target.itemId, "stills": result.list, "requested": count]
        value.merge(result.range) { $1 }
        if result.list.count < count {
            value["note"] = Date() >= deadline ? "Stopped after 60 s; the sheet shows what was decoded by then."
                : "Some times share a keyframe, so fewer stills than requested."
        }
        AppLog.info(.mcp, "frames \(target.itemId): \(result.list.count) stills")
        value[Self.imageKey] = jpeg
        return value
    }

    private static func position(_ text: String) throws -> Double {
        guard let value = Double(text) ?? seconds(text) else { throw ToolError("Positions are seconds or h:mm:ss: \(text)") }
        return value
    }

    nonisolated private static func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func subtitles(_ args: [String: Any]) async throws -> [String: Any] {
        guard let itemId = (args["item_id"] as? String) ?? nowPlaying()["item_id"] as? String else {
            throw ToolError("Nothing is playing; pass item_id.")
        }
        let parts = itemId.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == "jellyfin" else { throw ToolError("Subtitles are only available for Jellyfin items.") }
        guard app.hasJellyfin else { throw ToolError("No Jellyfin account") }
        let item = try await app.jellyfin.call { try await $0.item(userId: $1, id: parts[1]) }
        guard let source = item.mediaSources?.first, let sourceId = source.id else { throw ToolError("\(item.name) has no media file") }
        let subtitleStreams = (source.mediaStreams ?? []).filter { $0.type == "Subtitle" }
        let text = subtitleStreams.filter { $0.isTextSubtitleStream == true && $0.index != nil }
        guard !text.isEmpty else {
            throw ToolError(subtitleStreams.isEmpty ? "\(item.name) has no subtitles." : "\(item.name) has only image subtitles (no text subtitles).")
        }
        let chosen: JFMediaStream
        if let wanted = (args["language"] as? String)?.lowercased(), !wanted.isEmpty {
            guard let match = text.first(where: { $0.language?.lowercased() == wanted })
                    ?? text.first(where: { MediaNames.languageCode($0.language) == MediaNames.languageCode(wanted) && $0.language != nil })
                    ?? text.first(where: { ($0.displayTitle ?? $0.title ?? "").lowercased().contains(wanted) }) else {
                throw ToolError("No text subtitle track matches \(wanted).")
            }
            chosen = match
        } else if let playing = app.jellyfinPlayback, playing.item.id == item.id, let index = playing.subtitleIndex,
                  let match = text.first(where: { $0.index == index }) {
            chosen = match
        } else {
            chosen = text[0]
        }
        let srt = try await app.jellyfin.call { client, _ in try await client.subtitleSRT(itemId: item.id, mediaSourceId: sourceId, index: chosen.index!) }
        let from = try (args["from"] as? String ?? (args["from"] as? NSNumber)?.stringValue).map { try Self.position($0) } ?? 0
        let to = try (args["to"] as? String ?? (args["to"] as? NSNumber)?.stringValue).map { try Self.position($0) } ?? .infinity
        let cues = SRTParser.parse(srt).filter { $0.end >= from && $0.start <= to }
        let track = { (s: JFMediaStream) -> [String: Any] in
            var value: [String: Any] = ["index": s.index ?? -1, "title": s.displayTitle ?? s.title ?? "", "external": s.isExternal == true]
            if let language = s.language { value["language"] = language }
            return value
        }
        return [
            "item_id": itemId, "title": item.name, "tracks": text.map(track), "track": track(chosen), "count": cues.count,
            "cues": cues.map { ["start": Self.clock($0.start), "end": Self.clock($0.end),
                                "start_seconds": ($0.start * 10).rounded() / 10, "end_seconds": ($0.end * 10).rounded() / 10, "text": $0.text] },
        ]
    }

    // MARK: Player control

    private func playingEngine() throws -> PlayerEngine {
        guard app.nowPlaying != nil, let engine = app.playerEngine else { throw ToolError("Nothing is playing.") }
        return engine
    }

    /// `now_playing` once the player has settled (left buffering, at most 1.5 s).
    private func settled(_ extra: [String: Any] = [:]) async -> [String: Any] {
        for _ in 0..<15 {
            if let engine = app.playerEngine, engine.status != .buffering, engine.status != .loading { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nowPlaying().merging(extra) { $1 }
    }

    private func setPaused(_ paused: Bool) async throws -> [String: Any] {
        let engine = try playingEngine()
        engine.setPaused(paused)
        AppLog.info(.mcp, paused ? "paused" : "resumed")
        return await settled()
    }

    private func seek(_ args: [String: Any]) async throws -> [String: Any] {
        let engine = try playingEngine()
        let targets = ["by_seconds", "to_position", "to_time", "to_show_start", "to_live"].filter { args[$0] != nil && args[$0] as? Bool != false }
        guard targets.count == 1 else { throw ToolError("Pass exactly one of by_seconds, to_position, to_time, to_show_start, to_live.") }
        let progress = engine.progress
        let isLive = app.nowPlaying?.isLive == true
        if isLive && !engine.isTimeshift { throw ToolError("This channel plays without timeshift and cannot be rewound.") }
        let requested: Double
        switch targets[0] {
        case "by_seconds":
            guard let delta = (args["by_seconds"] as? NSNumber)?.doubleValue else { throw ToolError("by_seconds must be a number") }
            requested = progress.position + delta
            engine.seek(by: delta)
        case "to_position":
            guard !isLive else { throw ToolError("Live TV has no position; use by_seconds, to_time or to_show_start.") }
            let text = (args["to_position"] as? String) ?? (args["to_position"] as? NSNumber)?.stringValue ?? ""
            guard let target = Double(text) ?? Self.seconds(text) else { throw ToolError("to_position must be seconds or h:mm:ss") }
            requested = target
            engine.seek(to: target)
        case "to_live":
            guard isLive else { throw ToolError("Only live TV has a live edge.") }
            engine.goLive()
            AppLog.info(.mcp, "seek to live")
            return await settled()
        default:
            guard isLive, let wall = engine.wallTime(of: progress.position) ?? progress.wallClock else {
                throw ToolError("to_time and to_show_start work for live TV with timeshift.")
            }
            let targetTime: Date
            if targets[0] == "to_time" {
                guard let text = args["to_time"] as? String else { throw ToolError("to_time must be an ISO 8601 time") }
                targetTime = try Self.date(text)
            } else {
                guard case .live(let id, _)? = app.nowPlaying?.kind,
                      let show = entries(id).first(where: { $0.start <= wall && $0.end > wall }) else { throw ToolError("No program data for the current show.") }
                targetTime = show.start
            }
            let delta = targetTime.timeIntervalSince(wall)
            requested = progress.position + delta
            engine.seek(by: delta)
        }
        AppLog.info(.mcp, "seek \(targets[0])")
        let result = await settled()
        let reached = engine.progress.position
        guard abs(reached - requested) > 2 else { return result }
        let reason = isLive
            ? (requested < reached ? "The buffer only reaches back to \(result["buffer_starts_at"] as? String ?? "its start")." : "Seeking forward stops at the live edge.")
            : (requested < reached ? "The start is at 0:00:00." : "The end is at \(Self.clock(engine.progress.duration)).")
        return result.merging(["limited": true, "limit_reason": reason]) { $1 }
    }

    // MARK: Diagnostics

    private static let levels: [String: LogLevel] = ["error": .error, "warning": .warning, "info": .info, "detail": .detail]

    private static func entryJSON(_ entry: LogEntry) -> [String: Any] {
        ["time": iso(entry.date), "level": levels.first { $0.value == entry.level }?.key ?? "info", "category": entry.category.rawValue, "message": entry.message]
    }

    private func getLog(_ args: [String: Any]) -> [String: Any] {
        let previous = args["run"] as? String == "previous"
        let minutes = args["minutes"] as? Int ?? 30
        let limit = min(1000, max(1, args["limit"] as? Int ?? 200))
        let categories = (args["category"] as? String).flatMap(LogCategory.init).map { Set([$0]) } ?? []
        let result = AppLog.shared.query(previous: previous, minimum: Self.levels[args["level"] as? String ?? "info"] ?? .info,
                                         categories: categories, since: previous ? nil : Date().addingTimeInterval(-Double(minutes) * 60),
                                         query: args["query"] as? String ?? "", limit: limit)
        return ["run": previous ? "previous" : "current", "truncated": result.truncated, "entries": result.entries.map(Self.entryJSON)]
    }

    private func playbackDiagnostics() -> [String: Any] {
        var value = nowPlaying()
        if let engine = app.playerEngine, app.nowPlaying != nil {
            let s = engine.stats
            var stats: [String: Any] = [
                "buffer_seconds": (s.bufferSeconds * 10).rounded() / 10, "bitrate_mbps": (s.bitrateMbps * 10).rounded() / 10,
                "dropped_frames": s.droppedFrames, "decode_failures": s.decodeFailures, "rebuffers": s.rebuffers,
                "seamless_reconnects": s.seamlessReconnects, "reconnecting": s.isReconnecting, "restarts": s.restarts,
                "duplicates_dropped": s.duplicatesDropped, "startup_seconds": (s.startupTime * 100).rounded() / 100,
                "video_codec": s.videoCodec, "resolution": s.resolution, "frame_rate": (s.frameRate * 100).rounded() / 100,
                "decoder": s.decoder, "dynamic_range": s.dynamicRange, "audio": s.audio, "container": s.container,
            ]
            if let reason = s.lastReconnectReason { stats["last_reconnect_reason"] = reason }
            if let at = s.lastReconnectAt { stats["last_reconnect_at"] = Self.iso(at) }
            if let method = s.playMethod { stats["play_method"] = method }
            value["stats"] = stats
        } else {
            value["note"] = "Nothing is playing; recent warnings are still listed."
        }
        let recent = AppLog.shared.query(minimum: .warning, categories: [.player, .network, .tuner, .timeshift],
                                         since: Date().addingTimeInterval(-600), limit: 100)
        value["recent_warnings"] = recent.entries.map(Self.entryJSON)
        return value
    }

    /// "01:52:10", "112 min" or "6730" (as providers deliver it) in seconds.
    static func seconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        let digits = text.prefix { $0.isNumber }
        guard let number = Double(digits), number > 0 else { return nil }
        return text.contains("min") ? number * 60 : number
    }

    private func stopPlayback() -> [String: Any] {
        guard actions.stopPlayback() else { return ["result": "nothing_playing"] }
        AppLog.info(.mcp, "stopped playback")
        return ["result": "stopped"]
    }

    // MARK: Dates

    // Only read after setup; `frames` formats its labels off the main actor.
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter
    }()

    nonisolated static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

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

    /// A player window opened by `show` comes to the front once it appears (`appeared()`).
    private static var pendingFront = false

    /// Playback started from outside Fernsy (MCP, Siri): the player comes in front of every
    /// window without activating Fernsy, so the user's app keeps keyboard focus. A new window of
    /// a background app would otherwise open behind the active app's windows.
    static func show(_ app: AppModel) {
        guard !app.isPictureInPictureActive else { return }
        NSApp.setActivationPolicy(.regular)
        if let window, window.isVisible || window.isMiniaturized {
            if window.isMiniaturized { window.deminiaturize(nil) }
            orderFront()
            AppLog.detail(.app, "player window brought to the front")
            return
        }
        pendingFront = true
        open("player")
    }

    /// Called by the player when its window appears.
    static func appeared() {
        guard pendingFront else { return }
        pendingFront = false
        orderFront()
        AppLog.detail(.app, "new player window brought to the front")
    }

    /// SwiftUI orders a new window in after onAppear, and starting playback reorders an existing
    /// one; a single call is undone by that, so it repeats briefly.
    private static func orderFront() {
        for delay in [0, 0.15, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { window?.orderFrontRegardless() }
        }
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
