import AppKit
import CFFShim
import FernsyCore
import FernsyPlayer
import SwiftUI

/// The MCP tools: the guide, the viewing history, recordings and playback, through the same
/// functions and rules as the app's own views (hidden channels, adult content, stream limit).
@MainActor
final class MCPTools {
    typealias ToolError = AssistantTools.ToolError

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

    /// Shared with the in-app assistant (FernsyCore, cloud-assistant).
    static var definitions: [[String: Any]] { AssistantTools.definitions }

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
            "show_id": AssistantTools.showID(channel: channel.id, start: entry.start),
            "channel_id": channel.id, "channel": channel.displayName, "title": entry.title,
            "start": AssistantTools.iso(entry.start), "end": AssistantTools.iso(entry.end),
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

    private func program(_ args: [String: Any]) async throws -> [String: Any] {
        guard let id = args["channel_id"] as? Int else { throw ToolError("channel_id is required") }
        let channel = try visibleChannel(id)
        let (from, to) = try AssistantTools.range(args)
        await loadGuides([id])
        let shows = entries(id).filter { $0.end > from && $0.start < to }.sorted { $0.start < $1.start }
        return ["channel": channelJSON(channel), "from": AssistantTools.iso(from), "to": AssistantTools.iso(to), "shows": shows.map { showJSON($0, on: channel) }]
    }

    private func searchProgram(_ args: [String: Any]) async throws -> [String: Any] {
        let query = args["query"] as? String ?? ""
        guard !makeSearchKey(query.trimmingCharacters(in: .whitespaces)).isEmpty else { throw ToolError("query is required") }
        let channels = try scope(args)
        let from = try (args["from"] as? String).map(AssistantTools.date) ?? Date()
        let to = try (args["to"] as? String).map(AssistantTools.date) ?? .distantFuture
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
                let position = app.resumePosition(ResumeStore.movieKey(movie.id))
                guard position > 0 else { return nil }
                var value: [String: Any] = ["item_id": "movie:\(movie.id)", "title": movie.name, "position_seconds": Int(position)]
                if let fraction = app.resumeFraction(ResumeStore.movieKey(movie.id)) {
                    value["progress_percent"] = Int(fraction * 100)
                    value.merge(AssistantTools.runtime(duration: position / fraction, position: position)) { $1 }
                }
                return value
            }
        if app.hasJellyfin {
            result["jellyfin"] = ["continue_watching": app.jellyfin.resume.map(AssistantTools.jellyfinJSON), "next_up": app.jellyfin.nextUp.map(AssistantTools.jellyfinJSON)]
        }
        return result
    }

    // MARK: Recordings

    private func recordingJSON(_ recording: Recording) -> [String: Any] {
        var value: [String: Any] = [
            "recording_id": recording.id.uuidString, "channel_id": recording.channelId, "channel": recording.channelName,
            "title": recording.title, "status": recording.status.rawValue,
            "show_start": AssistantTools.iso(recording.start), "show_end": AssistantTools.iso(recording.end),
            "record_start": AssistantTools.iso(recording.recordStart), "record_end": AssistantTools.iso(recording.recordEnd),
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
        let (channelId, start) = try AssistantTools.show(args)
        let channel = try visibleChannel(channelId)
        await loadGuides([channelId])
        guard let entry = entries(channelId).first(where: { abs($0.start.timeIntervalSince(start)) < 60 }) else {
            throw ToolError("No show on \(channel.displayName) starts at \(AssistantTools.iso(start)); check get_program.")
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
        case ("cloud", 2):
            if app.cloud.items.isEmpty { await app.cloud.refresh() }
            guard let item = app.cloud.items.first(where: { $0.id == parts[1] }), item.meta != nil else {
                throw ToolError("No playable Fernsy Cloud recording with this id")
            }
            app.play(cloud: item)
        default:
            throw ToolError("item_id must be live:<id>, movie:<id>, episode:<series>:<episode>, jellyfin:<id>, recording:<id> or cloud:<id>")
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
        case .cloud(let id): value["item_id"] = "cloud:\(id)"
        case .jellyfin(let id, _, _): value["item_id"] = "jellyfin:\(id)"
        case .archive(let id, let start, _):
            value["item_id"] = "archive:\(id):\(Int(start.timeIntervalSince1970))"
            value["channel"] = app.channel(id)?.displayName
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
                var upcoming = AssistantTools.neighbourJSON(next, prefix: "next").reduce(into: [String: Any]()) { $0[String($1.key.dropFirst(5))] = $1.value }
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
                    value["rewind_available"] = AssistantTools.clock(rewind)
                    value["buffer_seconds"] = Int(max(0, progress.liveEnd - progress.liveStart))
                    value["buffer_limit_minutes"] = UserDefaults.standard.integer(forKey: AppModel.timeshiftMinutesKey)
                    if let wall = engine.wallTime(of: progress.position) ?? progress.wallClock {
                        let bufferStart = engine.wallTime(of: progress.liveStart) ?? wall.addingTimeInterval(-rewind)
                        value["buffer_starts_at"] = AssistantTools.iso(bufferStart)
                        if case .live(let id, _) = item.kind, let show = entries(id).first(where: { $0.start <= wall && $0.end > wall }) {
                            value["show_start_in_buffer"] = show.start >= bufferStart
                        }
                    }
                }
            } else if progress.duration > 0 {
                value.merge(AssistantTools.timing(position: progress.position, duration: progress.duration, running: engine.status == .playing)) { $1 }
            } else {
                value["position_seconds"] = Int(progress.position)
                value["position"] = AssistantTools.clock(progress.position)
            }
        }
        return value
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
            let position = app.resumePosition(ResumeStore.movieKey(id))
            let duration = details?.duration.flatMap(AssistantTools.seconds) ?? app.resumeFraction(ResumeStore.movieKey(id)).map { position / $0 }
            value.merge(AssistantTools.runtime(duration: duration, position: position)) { $1 }
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
            value.merge(AssistantTools.runtime(duration: episode.durationSeconds.map(Double.init), position: app.resumePosition(ResumeStore.episodeKey(episode.id)))) { $1 }
        case ("jellyfin", 2):
            guard app.hasJellyfin else { throw ToolError("No Jellyfin account") }
            let item = try await app.jellyfin.call { try await $0.item(userId: $1, id: parts[1]) }
            value.merge(AssistantTools.jellyfinJSON(item)) { $1 }
            value["title"] = item.name
            if let series = item.seriesName { value["series"] = series }
            if let season = item.parentIndexNumber { value["season"] = season }
            if let episode = item.indexNumber { value["episode"] = episode }
            if let year = item.productionYear { value["year"] = year }
            if let plot = item.overview, !plot.isEmpty { value["plot"] = plot }
            let streams = item.mediaSources?.first?.mediaStreams ?? []
            value["audio_tracks"] = streams.filter { $0.type == "Audio" }.map(AssistantTools.trackJSON)
            value["subtitle_tracks"] = streams.filter { $0.type == "Subtitle" }.map(AssistantTools.trackJSON)
            if item.type == "Episode", let seriesId = item.seriesId {
                let (previous, next) = AssistantTools.neighbours(of: item, in: try await seriesEpisodes(seriesId))
                if let previous { value.merge(AssistantTools.neighbourJSON(previous, prefix: "previous")) { $1 } }
                if let next { value.merge(AssistantTools.neighbourJSON(next, prefix: "next")) { $1 } }
            }
        case ("recording", 2):
            guard let id = UUID(uuidString: parts[1]), let recording = app.recorder.recordings.first(where: { $0.id == id }) else {
                throw ToolError("No recording with this id")
            }
            value.merge(recordingJSON(recording)) { $1 }
            value["type"] = "recording"
            if !recording.description.isEmpty { value["plot"] = recording.description }
            value.merge(AssistantTools.runtime(duration: recording.recordEnd.timeIntervalSince(recording.recordStart),
                                     position: app.resumePosition(ResumeStore.recordingKey(id)))) { $1 }
        default:
            throw ToolError("item_id must be movie:<id>, episode:<series>:<episode>, jellyfin:<id> or recording:<id>")
        }
        return value
    }

    /// A series' episodes ordered by season and episode number.
    private func seriesEpisodes(_ seriesId: String) async throws -> [JFItem] {
        AssistantTools.ordered(try await app.jellyfin.call { try await $0.seriesEpisodes(userId: $1, seriesId: seriesId) })
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
        let value: [String: Any] = ["series_id": "jellyfin:\(seriesId)", "series": item.seriesName ?? item.name]
        return value.merging(try AssistantTools.episodesJSON(episodes, season: (args["season"] as? NSNumber)?.intValue, seriesName: item.seriesName ?? item.name)) { $1 }
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
            if let wall = engine.wallTime(of: progress.position) ?? progress.wallClock { value["time"] = AssistantTools.iso(wall) }
        } else {
            value["position_seconds"] = Int(progress.position)
            value["position"] = AssistantTools.clock(progress.position)
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
            fromWall = try text("from").map(AssistantTools.date)
            toWall = try text("to").map(AssistantTools.date)
        } else {
            fromPos = try text("from").map { try AssistantTools.position($0) }
            toPos = try text("to").map { try AssistantTools.position($0) }
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
                        guard end > start else { throw ToolError("That time range is not in the buffer (\(AssistantTools.iso(oldest.wall)) to \(AssistantTools.iso(newest.wall))).") }
                        range = ["from": AssistantTools.iso(start), "to": AssistantTools.iso(end)]
                        let step = end.timeIntervalSince(start) / Double(count)
                        for i in 0..<count where Date() < deadline {
                            let wall = start.addingTimeInterval(step * (Double(i) + 0.5))
                            guard let entry = buffer.entry(atOrBeforeWall: wall), seen.insert(entry.offset).inserted,
                                  let still = grabber.still(atByte: source.position(ofBufferOffset: entry.offset)) else { continue }
                            let time = buffer.wallTime(of: still.streamTime - ffs_mux_delay()) ?? entry.wall
                            add(still, label: Self.clockTime(time), entry: ["time": AssistantTools.iso(time)])
                        }
                    } else {
                        let length = grabber.duration ?? 0
                        let start = max(0, fromPos ?? 0), end = min(toPos ?? length, length > 0 ? length : .infinity)
                        guard end.isFinite, end > start else { throw ToolError("The time range is empty or beyond the end (length \(AssistantTools.clock(length))).") }
                        range = ["from": AssistantTools.clock(start), "to": AssistantTools.clock(end), "length": AssistantTools.clock(length)]
                        let step = (end - start) / Double(count)
                        for i in 0..<count where Date() < deadline {
                            let position = start + step * (Double(i) + 0.5)
                            guard let still = grabber.still(atStreamTime: position + grabber.startTime) else { continue }
                            let shown = max(0, still.streamTime - grabber.startTime)
                            guard seen.insert(Int64(shown * 1000)).inserted else { continue }
                            add(still, label: AssistantTools.clock(shown), entry: ["position_seconds": Int(shown), "position": AssistantTools.clock(shown)])
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
        let playing = app.jellyfinPlayback.flatMap { $0.item.id == item.id ? $0.subtitleIndex : nil }
        let (sourceId, chosen) = try AssistantTools.subtitleTrack(of: item, wanted: (args["track"] as? NSNumber)?.intValue, playing: playing)
        let srt: String
        do {
            srt = try await app.jellyfin.call { client, _ in try await client.subtitleSRT(itemId: item.id, mediaSourceId: sourceId, index: chosen.index!) }
        } catch let error as URLError where error.code == .timedOut {
            throw ToolError("The Jellyfin server is still preparing these subtitles (it extracts them from the file on the first request). Try again in a minute.")
        }
        let from = try AssistantTools.text(args["from"]).map(AssistantTools.position) ?? 0
        let to = try AssistantTools.text(args["to"]).map(AssistantTools.position) ?? .infinity
        let cues = SRTParser.parse(srt).filter { $0.end >= from && $0.start <= to }
        return [
            "item_id": itemId, "title": item.name, "track": AssistantTools.trackJSON(chosen), "count": cues.count,
            "cues": cues.map { ["start": AssistantTools.clock($0.start), "end": AssistantTools.clock($0.end),
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
        let target = try AssistantTools.seekTarget(args)
        let progress = engine.progress
        let isLive = app.nowPlaying?.isLive == true
        if isLive && !engine.isTimeshift { throw ToolError("This channel plays without timeshift and cannot be rewound.") }
        let requested: Double
        switch target {
        case "by_seconds":
            guard let delta = (args["by_seconds"] as? NSNumber)?.doubleValue else { throw ToolError("by_seconds must be a number") }
            requested = progress.position + delta
            engine.seek(by: delta)
        case "to_position":
            guard !isLive else { throw ToolError("Live TV has no position; use by_seconds, to_time or to_show_start.") }
            let text = AssistantTools.text(args["to_position"]) ?? ""
            guard let position = Double(text) ?? AssistantTools.seconds(text) else { throw ToolError("to_position must be seconds or h:mm:ss") }
            requested = position
            engine.seek(to: position)
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
            if target == "to_time" {
                guard let text = args["to_time"] as? String else { throw ToolError("to_time must be an ISO 8601 time") }
                targetTime = try AssistantTools.date(text)
            } else {
                guard case .live(let id, _)? = app.nowPlaying?.kind,
                      let show = entries(id).first(where: { $0.start <= wall && $0.end > wall }) else { throw ToolError("No program data for the current show.") }
                targetTime = show.start
            }
            let delta = targetTime.timeIntervalSince(wall)
            requested = progress.position + delta
            engine.seek(by: delta)
        }
        AppLog.info(.mcp, "seek \(target)")
        let result = await settled()
        let reached = engine.progress.position
        guard abs(reached - requested) > 2 else { return result }
        let reason = isLive
            ? (requested < reached ? "The buffer only reaches back to \(result["buffer_starts_at"] as? String ?? "its start")." : "Seeking forward stops at the live edge.")
            : (requested < reached ? "The start is at 0:00:00." : "The end is at \(AssistantTools.clock(engine.progress.duration)).")
        return result.merging(["limited": true, "limit_reason": reason]) { $1 }
    }

    // MARK: Diagnostics

    private static let levels: [String: LogLevel] = ["error": .error, "warning": .warning, "info": .info, "detail": .detail]

    private static func entryJSON(_ entry: LogEntry) -> [String: Any] {
        ["time": AssistantTools.iso(entry.date), "level": levels.first { $0.value == entry.level }?.key ?? "info", "category": entry.category.rawValue, "message": entry.message]
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
            if let at = s.lastReconnectAt { stats["last_reconnect_at"] = AssistantTools.iso(at) }
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

    private func stopPlayback() -> [String: Any] {
        guard actions.stopPlayback() else { return ["result": "nothing_playing"] }
        AppLog.info(.mcp, "stopped playback")
        return ["result": "stopped"]
    }

}
