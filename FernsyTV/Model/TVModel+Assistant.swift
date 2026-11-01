import FernsyCore
import FernsyPlayer
import Foundation
import UIKit

extension TVModel {
    /// The assistant with this model's tools; it asks before a tool removes something. The Apple
    /// TV takes one request at a time, iPad and iPhone keep the session's conversation.
    func makeAssistant() -> AssistantModel {
        let runner = AssistantToolRunner(model: self)
        #if os(tvOS)
        let assistant = AssistantModel(cloud: cloud, platform: "Apple TV", keepHistory: false) { try await runner.call($0, $1) }
        #else
        let platform = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        let assistant = AssistantModel(cloud: cloud, platform: platform) { [weak self] name, args in
            // The player covers everything: the sheet goes first, or it could not show.
            if name == "play", self?.showsAssistant == true {
                self?.showsAssistant = false
                try? await Task.sleep(for: .milliseconds(600))
            }
            return try await runner.call(name, args)
        }
        #endif
        runner.confirm = { [weak assistant] question in await assistant?.confirm(question) ?? false }
        return assistant
    }
}

/// The in-app assistant's tools on Apple TV, iPad and iPhone (cloud-assistant design 4): the
/// names, arguments and results of the Mac's MCP tools (`AssistantTools`), run against TVModel
/// with its rules (hidden channels, adult content, favourites and recently watched, the stream
/// limit). iPad and iPhone do not record, so the recording tools say so there.
@MainActor
final class AssistantToolRunner {
    typealias ToolError = AssistantTools.ToolError

    private unowned let model: TVModel
    /// Asked before a tool removes something (design 5), with the question to show; the UI sets
    /// it. Without one nothing is removed.
    var confirm: (String) async -> Bool = { _ in false }

    init(model: TVModel) { self.model = model }

    func call(_ name: String, _ args: [String: Any]) async throws -> [String: Any] {
        switch name {
        case "find_channels": return findChannels(args)
        case "whats_on": return try await whatsOn(args)
        case "get_program": return try await program(args)
        case "search_program": return try await searchProgram(args)
        case "recently_watched": return recentlyWatched()
        case "list_recordings": return try listRecordings(args)
        case "schedule_recording": return try await scheduleRecording(args)
        case "cancel_recording": return try await cancelRecording(args)
        case "play": return try await play(args)
        case "now_playing": return nowPlaying()
        case "item_info": return try await itemInfo(args)
        case "list_episodes": return try await listEpisodes(args)
        case "get_subtitles": return try await subtitles(args)
        case "pause": return try await setPaused(true)
        case "resume": return try await setPaused(false)
        case "seek": return try await seek(args)
        case "stop_playback": return stopPlayback()
        default: throw ToolError("\(name) is not available on this device.")
        }
    }

    // MARK: Channels and guide

    private func visibleChannel(_ id: Int) throws -> LiveChannel {
        guard let channel = model.channels(for: .all).first(where: { $0.id == id }) else { throw ToolError("No visible channel with id \(id)") }
        return channel
    }

    private func findChannels(_ args: [String: Any]) -> [String: Any] {
        let category = (args["category"] as? String).flatMap { name in
            model.visibleCategories.first { $0.id == name || makeSearchKey($0.displayName) == makeSearchKey(name) || makeSearchKey($0.name) == makeSearchKey(name) }
        }
        let limit = min(200, max(1, args["limit"] as? Int ?? 50))
        var list = model.channels(for: category.map { .category($0.id) } ?? .all)
        let needle = makeSearchKey(args["query"] as? String ?? "")
        if !needle.isEmpty { list = list.filter { $0.searchKey.contains(needle) } }
        if args["favorites_only"] as? Bool == true { list = list.filter { model.isFavorite($0) } }
        var result: [String: Any] = [:]
        if needle.isEmpty && category == nil && args["favorites_only"] == nil {
            let counts = Dictionary(grouping: model.channels(for: .all)) { $0.categoryId ?? "" }.mapValues(\.count)
            result["categories"] = model.visibleCategories.map { ["id": $0.id, "name": $0.displayName, "channels": counts[$0.id] ?? 0] }
            list = list.filter { model.isFavorite($0) }
            result["note"] = "Without arguments only favourite channels are listed."
        } else if let name = args["category"] as? String, category == nil {
            result["note"] = "No category named \(name); searched all channels."
        }
        result["total"] = list.count
        result["channels"] = list.prefix(limit).map(channelJSON)
        return result
    }

    private func channelJSON(_ channel: LiveChannel) -> [String: Any] {
        var value: [String: Any] = ["id": channel.id, "name": channel.displayName, "favorite": model.isFavorite(channel)]
        if let category = model.categories.first(where: { $0.id == channel.categoryId }) { value["category"] = category.displayName }
        return value
    }

    private func loadGuides(_ ids: [Int], timeout: TimeInterval = 20) async {
        await model.guide.load(ids, client: model.client, timeout: timeout)
    }

    private func entries(_ channelId: Int) -> [EPGEntry] { model.guide.guide(channelId).entries ?? [] }

    private func showJSON(_ entry: EPGEntry, on channel: LiveChannel) -> [String: Any] {
        var value: [String: Any] = [
            "show_id": AssistantTools.showID(channel: channel.id, start: entry.start),
            "channel_id": channel.id, "channel": channel.displayName, "title": entry.title,
            "start": AssistantTools.iso(entry.start), "end": AssistantTools.iso(entry.end),
        ]
        if !entry.description.isEmpty { value["description"] = String(entry.description.prefix(300)) }
        if let recording = model.recorder.recordings.first(where: { $0.matches(channelId: channel.id, entry: entry) && $0.status != .skipped }) {
            value["recording"] = ["recording_id": recording.id.uuidString, "status": recording.status.rawValue]
        }
        return value
    }

    /// Given ids (visible ones), or favourites plus recently watched.
    private func scope(_ args: [String: Any]) throws -> [LiveChannel] {
        if let ids = args["channel_ids"] as? [Int], !ids.isEmpty {
            let visible = Dictionary(model.channels(for: .all).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return Array(ids.compactMap { visible[$0] }.prefix(AssistantTools.channelLimit))
        }
        var seen = Set<Int>()
        let list = (model.channels(for: .favorites) + model.channels(for: .recent)).filter { seen.insert($0.id).inserted }
        guard !list.isEmpty else { throw ToolError("No favourite or recently watched channels; pass channel_ids (see find_channels).") }
        return Array(list.prefix(AssistantTools.channelLimit))
    }

    private func whatsOn(_ args: [String: Any]) async throws -> [String: Any] {
        let channels = try scope(args)
        await loadGuides(channels.map(\.id))
        return ["channels": channels.map { channel -> [String: Any] in
            let (current, next) = model.guide.nowAndNext(channel.id)
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
        await loadGuides(channels.map(\.id), timeout: 30)
        let hits = model.guide.search(query, on: channels, from: from, to: to)
        return ["searched_channels": channels.map { ["id": $0.id, "name": $0.displayName] },
                "shows": hits.prefix(100).map { showJSON($0.entry, on: $0.channel) }]
    }

    // MARK: History

    private func recentlyWatched() -> [String: Any] {
        let now = Date()
        var result: [String: Any] = [
            "live": model.channels(for: .recent).map { channel -> [String: Any] in
                var value = channelJSON(channel)
                if let current = model.currentShow(on: channel, at: now) { value["now"] = current.title }
                return value
            },
        ]
        // The film list holds no adult films on these devices (TVModel+Library.swift).
        result["iptv_films_in_progress"] = model.movies.compactMap { movie -> [String: Any]? in
            let key = ResumeStore.movieKey(movie.id)
            let position = model.resume.position(key)
            guard position > 0 else { return nil }
            var value: [String: Any] = ["item_id": "movie:\(movie.id)", "title": movie.name, "position_seconds": Int(position)]
            if let fraction = model.resume.fraction(key) {
                value["progress_percent"] = Int(fraction * 100)
                value.merge(AssistantTools.runtime(duration: position / fraction, position: position)) { $1 }
            }
            return value
        }
        if model.jellyfin.session != nil {
            result["jellyfin"] = ["continue_watching": model.jellyfin.resume.map(AssistantTools.jellyfinJSON),
                                  "next_up": model.jellyfin.nextUp.map(AssistantTools.jellyfinJSON)]
        }
        return result
    }

    // MARK: Recordings

    /// iPad and iPhone do not record (ios-app: no recordings on iPhone and iPad).
    private func requireRecorder() throws {
        #if os(iOS)
        throw ToolError("Recordings are made on the Mac or the Apple TV; Fernsy on iPhone and iPad does not record.")
        #endif
    }

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

    private func listRecordings(_ args: [String: Any]) throws -> [String: Any] {
        try requireRecorder()
        let status = args["status"] as? String ?? "all"
        let list = model.recorder.recordings
            .filter { status == "all" || $0.status.rawValue == status }
            .sorted { $0.recordStart < $1.recordStart }
        return ["recordings": list.map(recordingJSON)]
    }

    private func scheduleRecording(_ args: [String: Any]) async throws -> [String: Any] {
        try requireRecorder()
        let (channelId, start) = try AssistantTools.show(args)
        let channel = try visibleChannel(channelId)
        await loadGuides([channelId])
        guard let entry = entries(channelId).first(where: { abs($0.start.timeIntervalSince(start)) < 60 }) else {
            throw ToolError("No show on \(channel.displayName) starts at \(AssistantTools.iso(start)); check get_program.")
        }
        guard entry.end > Date() else { throw ToolError("„\(entry.title)“ has already ended.") }
        switch model.recorder.schedule(entry, on: channel) {
        case .refused(let reason):
            return ["result": "refused", "reason": reason]
        case .planned(let notice):
            var value: [String: Any] = ["result": notice == nil ? "planned" : "planned_with_shortened_padding"]
            if let notice { value["notice"] = notice }
            if let recording = model.recorder.recordings.first(where: { $0.matches(channelId: channel.id, entry: entry) && $0.isUpcomingOrRunning }) {
                value["recording"] = recordingJSON(recording)
            }
            return value
        }
    }

    private func cancelRecording(_ args: [String: Any]) async throws -> [String: Any] {
        try requireRecorder()
        guard let text = args["recording_id"] as? String, let id = UUID(uuidString: text),
              let recording = model.recorder.recordings.first(where: { $0.id == id }) else { throw ToolError("No recording with this id") }
        guard recording.status == .scheduled else {
            throw ToolError("Only scheduled recordings can be cancelled; „\(recording.title)“ is \(recording.status.rawValue). Its file is kept.")
        }
        let when = ItemText.channelAndTime(recording.channelName, recording.start)
        guard await confirm(String(localized: "Remove the scheduled recording of “\(recording.title)” (\(when))?")) else {
            return ["result": "kept", "recording_id": text, "reason": "The user did not confirm; the recording stays scheduled."]
        }
        // Asked and answered: it may have started meanwhile.
        guard model.recorder.recordings.first(where: { $0.id == id })?.status == .scheduled else {
            throw ToolError("„\(recording.title)“ is no longer scheduled; nothing was changed.")
        }
        model.recorder.stop(id)
        AppLog.info(.app, "assistant cancelled \(recording.title)")
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
            // Never ends a running recording: no question, the person asking may be elsewhere.
            let held = model.tuners.blockers(for: channel.id, as: .player)
            if let first = model.recorder.recordings.first(where: { r in r.status == .recording && held.contains { $0.owners.contains(.recording(r.id)) } }) {
                return ["result": "blocked",
                        "reason": "„\(first.title)“ is being recorded on \(first.channelName) and the account allows \(model.tuners.limit) stream(s). Playing \(channel.displayName) would end that recording; nothing was changed."]
            }
            if model.playingVOD != nil { model.stopVOD() }
            model.play(channel)
        case ("movie", 2):
            guard let id = Int(parts[1]), let movie = model.moviesByID[id] else { throw ToolError("No IPTV film with this id") }
            model.play(.movie(movie))
        case ("episode", 3):
            guard let seriesId = Int(parts[1]), let show = model.seriesByID[seriesId] else { throw ToolError("No IPTV series with this id") }
            let episode = try await iptvEpisode(parts[2], of: show)
            model.play(.episode(episode, show))
        case ("jellyfin", 2):
            var item = try await jellyfinItem(parts[1])
            // A series starts with its Next Up episode, as on the Mac.
            if item.isSeries {
                guard let episode = await model.jellyfin.episodeToPlay(seriesId: item.id) else { throw ToolError("\(item.name) has no episode to play") }
                item = episode
            }
            model.play(.jellyfin(item))
        case ("recording", 2):
            guard let id = UUID(uuidString: parts[1]), let recording = model.startRecording(id),
                  let url = model.recorder.fileURL(recording), FileManager.default.fileExists(atPath: url.path) else {
                throw ToolError("No recording with a file and this id")
            }
            model.play(recording)
        case ("cloud", 2):
            if model.cloud.items.isEmpty { await model.cloud.refresh() }
            guard let item = model.cloud.items.first(where: { $0.id == parts[1] }), item.meta != nil else {
                throw ToolError("No playable Fernsy Cloud recording with this id")
            }
            model.play(.cloud(item))
        default:
            throw ToolError("item_id must be live:<id>, movie:<id>, episode:<series>:<episode>, jellyfin:<id>, recording:<id> or cloud:<id>")
        }
        AppLog.info(.app, "assistant plays \(itemId)")
        return ["result": "playing", "item_id": itemId]
    }

    private func iptvEpisode(_ id: String, of show: Series) async throws -> Episode {
        guard let info = await model.seriesDetails(show) else { throw ToolError("The episodes of \(show.name) could not be loaded") }
        guard let episode = info.seasons.values.joined().first(where: { $0.id == id }) else { throw ToolError("No episode \(id) in \(show.name)") }
        return episode
    }

    private func jellyfinItem(_ id: String) async throws -> JFItem {
        guard model.jellyfin.session != nil else { throw ToolError("No Jellyfin account") }
        return try await model.jellyfin.call { try await $0.item(userId: $1, id: id) }
    }

    private var isPlaying: Bool { model.playing != nil || model.playingVOD != nil || model.playingRecording != nil }

    private func nowPlaying() -> [String: Any] {
        var value: [String: Any] = ["playing": true]
        if let channel = model.playing {
            value["title"] = channel.displayName
            value["item_id"] = "live:\(channel.id)"
            value["channel"] = channel.displayName
            if let current = model.currentShow(on: channel) { value["show"] = showJSON(current, on: channel) }
        } else if let recording = model.playingRecording {
            value["title"] = recording.title
            value["subtitle"] = ItemText.channelAndTime(recording.channelName, recording.start)
            value["item_id"] = "recording:\(recording.id.uuidString)"
        } else if let item = model.playingVOD {
            value["title"] = item.title
            if let subtitle = item.subtitle { value["subtitle"] = subtitle }
            switch item {
            case .movie(let movie): value["item_id"] = "movie:\(movie.id)"
            case .episode(let episode, let show): value["item_id"] = "episode:\(show.id):\(episode.id)"
            case .jellyfin(let jfItem): value["item_id"] = "jellyfin:\(jfItem.id)"
            case .cloud(let cloudItem): value["item_id"] = "cloud:\(cloudItem.id)"
            case .archive(let show, let channel):
                value["item_id"] = "archive:\(channel.id):\(Int(show.start.timeIntervalSince1970))"
                value["channel"] = channel.displayName
            }
        } else {
            return ["playing": false]
        }
        let engine = model.engine, progress = engine.progress
        value["state"] = switch engine.status {
        case .playing: "playing"
        case .paused: "paused"
        case .buffering, .loading: "buffering"
        case .ended: "ended"
        case .idle: "idle"
        case .failed(let message): "failed: \(message)"
        }
        if engine.status == .ended, case .jellyfin? = model.playingVOD, let playback = model.jellyfinPlayback, let next = playback.nextEpisode {
            var upcoming = AssistantTools.neighbourJSON(next, prefix: "next").reduce(into: [String: Any]()) { $0[String($1.key.dropFirst(5))] = $1.value }
            if let at = playback.autoplayAt { upcoming["starts_in_seconds"] = max(0, Int(at.timeIntervalSinceNow.rounded(.up))) }
            else if playback.autoplayCancelled { upcoming["autoplay_cancelled"] = true }
            value["next"] = upcoming
        }
        if let channel = model.playing {
            value["follows_live"] = progress.followsLive
            if !progress.followsLive { value["behind_live_seconds"] = Int(progress.behindLive) }
            value["timeshift"] = engine.isTimeshift
            if engine.isTimeshift {
                let rewind = max(0, progress.position - progress.liveStart)
                value["rewind_available_seconds"] = Int(rewind)
                value["rewind_available"] = AssistantTools.clock(rewind)
                value["buffer_seconds"] = Int(max(0, progress.liveEnd - progress.liveStart))
                value["buffer_limit_minutes"] = Int(TVModel.timeshiftSeconds / 60)
                if let wall = engine.wallTime(of: progress.position) ?? progress.wallClock {
                    let bufferStart = engine.wallTime(of: progress.liveStart) ?? wall.addingTimeInterval(-rewind)
                    value["buffer_starts_at"] = AssistantTools.iso(bufferStart)
                    if let show = model.currentShow(on: channel, at: wall) { value["show_start_in_buffer"] = show.start >= bufferStart }
                }
            }
        } else if progress.duration > 0 {
            value.merge(AssistantTools.timing(position: progress.position, duration: progress.duration, running: engine.status == .playing)) { $1 }
        } else {
            value["position_seconds"] = Int(progress.position)
            value["position"] = AssistantTools.clock(progress.position)
        }
        return value
    }

    private func itemInfo(_ args: [String: Any]) async throws -> [String: Any] {
        guard let itemId = args["item_id"] as? String else { throw ToolError("item_id is required") }
        let parts = itemId.split(separator: ":", maxSplits: 2).map(String.init)
        var value: [String: Any] = ["item_id": itemId]
        switch (parts.first, parts.count) {
        case ("movie", 2):
            guard let id = Int(parts[1]), let movie = model.moviesByID[id] else { throw ToolError("No IPTV film with this id") }
            value["type"] = "film"
            value["title"] = movie.name
            let details = await model.movieDetails(movie)
            if let plot = details?.plot, !plot.isEmpty { value["plot"] = plot }
            if let genre = details?.genre { value["genre"] = genre }
            if let date = details?.releaseDate { value["release_date"] = date }
            let key = ResumeStore.movieKey(id)
            let position = model.resume.position(key)
            let duration = details?.duration.flatMap(AssistantTools.seconds) ?? model.resume.fraction(key).map { position / $0 }
            value.merge(AssistantTools.runtime(duration: duration, position: position)) { $1 }
        case ("episode", 3):
            guard let seriesId = Int(parts[1]), let show = model.seriesByID[seriesId] else { throw ToolError("No IPTV series with this id") }
            let episode = try await iptvEpisode(parts[2], of: show)
            value["type"] = "episode"
            value["series"] = show.name
            value["season"] = episode.season
            value["episode"] = episode.number
            value["title"] = episode.title
            if let plot = episode.plot, !plot.isEmpty { value["plot"] = plot }
            value.merge(AssistantTools.runtime(duration: episode.durationSeconds.map(Double.init),
                                               position: model.resume.position(ResumeStore.episodeKey(episode.id)))) { $1 }
        case ("jellyfin", 2):
            let item = try await jellyfinItem(parts[1])
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
            guard let id = UUID(uuidString: parts[1]), let recording = model.startRecording(id) else { throw ToolError("No recording with this id") }
            value.merge(recordingJSON(recording)) { $1 }
            value["type"] = "recording"
            if !recording.description.isEmpty { value["plot"] = recording.description }
            value.merge(AssistantTools.runtime(duration: recording.recordEnd.timeIntervalSince(recording.recordStart),
                                               position: model.resumePosition(recording))) { $1 }
        default:
            throw ToolError("item_id must be movie:<id>, episode:<series>:<episode>, jellyfin:<id> or recording:<id>")
        }
        return value
    }

    private func seriesEpisodes(_ seriesId: String) async throws -> [JFItem] {
        AssistantTools.ordered(try await model.jellyfin.call { try await $0.seriesEpisodes(userId: $1, seriesId: seriesId) })
    }

    private func listEpisodes(_ args: [String: Any]) async throws -> [String: Any] {
        guard let raw = args["series_id"] as? String, !raw.isEmpty else { throw ToolError("series_id is required") }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 ? parts[0] == "jellyfin" : true else {
            throw ToolError("list_episodes is only available for Jellyfin series (jellyfin:<id>).")
        }
        let item = try await jellyfinItem(parts.last!)
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

    private func subtitles(_ args: [String: Any]) async throws -> [String: Any] {
        guard let itemId = (args["item_id"] as? String) ?? nowPlaying()["item_id"] as? String else {
            throw ToolError("Nothing is playing; pass item_id.")
        }
        let parts = itemId.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == "jellyfin" else { throw ToolError("Subtitles are only available for Jellyfin items.") }
        let item = try await jellyfinItem(parts[1])
        let playing = model.jellyfinPlayback.flatMap { $0.item.id == item.id ? $0.subtitleIndex : nil }
        let (sourceId, chosen) = try AssistantTools.subtitleTrack(of: item, wanted: (args["track"] as? NSNumber)?.intValue, playing: playing)
        let srt: String
        do {
            srt = try await model.jellyfin.call { client, _ in try await client.subtitleSRT(itemId: item.id, mediaSourceId: sourceId, index: chosen.index!) }
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
        guard isPlaying else { throw ToolError("Nothing is playing.") }
        return model.engine
    }

    /// `now_playing` once the player has settled (left buffering, at most 1.5 s).
    private func settled() async -> [String: Any] {
        for _ in 0..<15 {
            if model.engine.status != .buffering, model.engine.status != .loading { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nowPlaying()
    }

    private func setPaused(_ paused: Bool) async throws -> [String: Any] {
        try playingEngine().setPaused(paused)
        return await settled()
    }

    private func seek(_ args: [String: Any]) async throws -> [String: Any] {
        let engine = try playingEngine()
        let target = try AssistantTools.seekTarget(args)
        let progress = engine.progress
        let live = model.playing
        if live != nil && !engine.isTimeshift { throw ToolError("This channel plays without timeshift and cannot be rewound.") }
        let requested: Double
        switch target {
        case "by_seconds":
            guard let delta = (args["by_seconds"] as? NSNumber)?.doubleValue else { throw ToolError("by_seconds must be a number") }
            requested = progress.position + delta
            engine.seek(by: delta)
        case "to_position":
            guard live == nil else { throw ToolError("Live TV has no position; use by_seconds, to_time or to_show_start.") }
            let text = AssistantTools.text(args["to_position"]) ?? ""
            guard let position = Double(text) ?? AssistantTools.seconds(text) else { throw ToolError("to_position must be seconds or h:mm:ss") }
            requested = position
            engine.seek(to: position)
        case "to_live":
            guard live != nil else { throw ToolError("Only live TV has a live edge.") }
            engine.goLive()
            return await settled()
        default:
            guard let live, let wall = engine.wallTime(of: progress.position) ?? progress.wallClock else {
                throw ToolError("to_time and to_show_start work for live TV with timeshift.")
            }
            let targetTime: Date
            if target == "to_time" {
                guard let text = args["to_time"] as? String else { throw ToolError("to_time must be an ISO 8601 time") }
                targetTime = try AssistantTools.date(text)
            } else {
                guard let show = model.currentShow(on: live, at: wall) else { throw ToolError("No program data for the current show.") }
                targetTime = show.start
            }
            let delta = targetTime.timeIntervalSince(wall)
            requested = progress.position + delta
            engine.seek(by: delta)
        }
        let result = await settled()
        let reached = engine.progress.position
        guard abs(reached - requested) > 2 else { return result }
        let reason = live != nil
            ? (requested < reached ? "The buffer only reaches back to \(result["buffer_starts_at"] as? String ?? "its start")." : "Seeking forward stops at the live edge.")
            : (requested < reached ? "The start is at 0:00:00." : "The end is at \(AssistantTools.clock(engine.progress.duration)).")
        return result.merging(["limited": true, "limit_reason": reason]) { $1 }
    }

    private func stopPlayback() -> [String: Any] {
        guard isPlaying else { return ["result": "nothing_playing"] }
        model.stop()
        return ["result": "stopped"]
    }
}
