import Foundation

/// The tools' argument and result formats, shared by the Mac's MCP server and the tool runners
/// of Apple TV and iOS (cloud-assistant design 4), so every platform reads and answers alike:
/// ISO times in the device's time zone, positions as seconds or h:mm:ss, show ids
/// "<channel>:<start epoch>", and the JSON of Jellyfin items and tracks.
extension AssistantTools {
    /// A tool's failure; its message goes to the model, which can explain it or try another way.
    public struct ToolError: LocalizedError {
        public let errorDescription: String?
        public init(_ message: String) { errorDescription = message }
    }

    // MARK: Times

    // Only read after setup; the Mac's `frames` formats labels off the main actor.
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter
    }()

    public static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }

    /// An ISO 8601 time; without an offset, in the device's time zone.
    public static func date(_ text: String) throws -> Date {
        if let date = isoFormatter.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: text) { return date }
        }
        throw ToolError("Not an ISO 8601 date: \(text)")
    }

    /// `from` and `to` of a guide query: by default now and 24 hours later.
    public static func range(_ args: [String: Any], now: Date = Date()) throws -> (from: Date, to: Date) {
        let from = try (args["from"] as? String).map(date) ?? now
        let to = try (args["to"] as? String).map(date) ?? from.addingTimeInterval(24 * 3600)
        guard to > from else { throw ToolError("'to' must be after 'from'") }
        return (from, to)
    }

    // MARK: Positions

    public static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }

    /// "01:52:10", "112 min" or "6730" (as providers deliver it) in seconds.
    public static func seconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        let digits = text.prefix { $0.isNumber }
        guard let number = Double(digits), number > 0 else { return nil }
        return text.contains("min") ? number * 60 : number
    }

    /// A position argument: seconds or h:mm:ss.
    public static func position(_ text: String) throws -> Double {
        guard let value = Double(text) ?? seconds(text) else { throw ToolError("Positions are seconds or h:mm:ss: \(text)") }
        return value
    }

    /// An argument the model may send as a string or a number.
    public static func text(_ value: Any?) -> String? {
        (value as? String) ?? (value as? NSNumber)?.stringValue
    }

    /// Position, duration and what is left, as seconds and h:mm:ss, plus the end time while it plays.
    public static func timing(position: Double, duration: Double, running: Bool, now: Date = Date()) -> [String: Any] {
        let remaining = max(0, duration - position)
        var value: [String: Any] = [
            "position_seconds": Int(position), "position": clock(position),
            "duration_seconds": Int(duration), "duration": clock(duration),
            "remaining_seconds": Int(remaining), "remaining": clock(remaining),
        ]
        if running { value["ends_at"] = iso(now.addingTimeInterval(remaining)) }
        return value
    }

    /// Runtime and, once started, what is left.
    public static func runtime(duration: Double?, position: Double?) -> [String: Any] {
        guard let duration, duration > 0 else { return [:] }
        var value: [String: Any] = ["runtime_seconds": Int(duration), "runtime": clock(duration)]
        if let position, position > 0 {
            value["position"] = clock(position)
            value["remaining_seconds"] = Int(max(0, duration - position))
            value["remaining"] = clock(max(0, duration - position))
        }
        return value
    }

    // MARK: Shows and seeking

    public static func showID(channel: Int, start: Date) -> String { "\(channel):\(Int(start.timeIntervalSince1970))" }

    /// The show a recording request names: `show_id`, or `channel_id` and `start`.
    public static func show(_ args: [String: Any]) throws -> (channelId: Int, start: Date) {
        if let showId = args["show_id"] as? String {
            let parts = showId.split(separator: ":")
            guard parts.count == 2, let id = Int(parts[0]), let epoch = Double(parts[1]) else { throw ToolError("show_id must look like <channel>:<start epoch>") }
            return (id, Date(timeIntervalSince1970: epoch))
        }
        if let id = args["channel_id"] as? Int, let text = args["start"] as? String { return (id, try date(text)) }
        throw ToolError("Pass show_id, or channel_id and start")
    }

    /// The one target `seek` was given (a `false` flag does not count).
    public static func seekTarget(_ args: [String: Any]) throws -> String {
        let targets = ["by_seconds", "to_position", "to_time", "to_show_start", "to_live"].filter { args[$0] != nil && args[$0] as? Bool != false }
        guard targets.count == 1 else { throw ToolError("Pass exactly one of by_seconds, to_position, to_time, to_show_start, to_live.") }
        return targets[0]
    }

    // MARK: Jellyfin

    /// A Jellyfin item as the history and episode lists show it.
    public static func jellyfinJSON(_ item: JFItem) -> [String: Any] {
        var title = item.name
        if item.type == "Episode", let series = item.seriesName {
            let code = [item.parentIndexNumber.map { "S\($0)" }, item.indexNumber.map { "E\($0)" }].compactMap { $0 }.joined()
            title = "\(series) \(code) · \(item.name)"
        }
        var value: [String: Any] = ["item_id": "jellyfin:\(item.id)", "title": title, "type": item.type]
        if let percent = item.userData?.playedPercentage { value["progress_percent"] = Int(percent) }
        value.merge(runtime(duration: item.runTimeSeconds, position: item.userData?.playbackPositionTicks.map(JellyfinTicks.seconds))) { $1 }
        return value
    }

    /// An audio or subtitle track as item_info lists it (and get_subtitles names it).
    public static func trackJSON(_ stream: JFMediaStream) -> [String: Any] {
        var value: [String: Any] = [
            "index": stream.index ?? -1, "title": stream.displayTitle ?? stream.title ?? "",
            "default": stream.isDefault == true, "external": stream.isExternal == true,
        ]
        if let language = stream.language { value["language"] = language }
        if stream.type == "Subtitle" {
            value["forced"] = stream.isForced == true || MediaNames.titleSaysForced(stream.title) || MediaNames.titleSaysForced(stream.displayTitle)
            value["text"] = stream.isTextSubtitleStream == true
        }
        return value
    }

    /// The previous or next episode, its keys prefixed ("next_item_id", …).
    public static func neighbourJSON(_ item: JFItem, prefix: String) -> [String: Any] {
        var value: [String: Any] = ["\(prefix)_item_id": "jellyfin:\(item.id)", "\(prefix)_title": item.name]
        if let season = item.parentIndexNumber { value["\(prefix)_season"] = season }
        if let episode = item.indexNumber { value["\(prefix)_episode"] = episode }
        return value
    }

    /// A series' episodes ordered by season and episode number.
    public static func ordered(_ episodes: [JFItem]) -> [JFItem] {
        episodes.sorted { ($0.parentIndexNumber ?? 0, $0.indexNumber ?? 0) < ($1.parentIndexNumber ?? 0, $1.indexNumber ?? 0) }
    }

    /// The episodes before and after `item` in its run (specials only neighbour specials;
    /// regular episodes skip season 0), from `episodes` in order.
    public static func neighbours(of item: JFItem, in episodes: [JFItem]) -> (previous: JFItem?, next: JFItem?) {
        let isSpecial = item.parentIndexNumber == 0
        let run = episodes.filter { ($0.parentIndexNumber == 0) == isSpecial }
        guard let index = run.firstIndex(where: { $0.id == item.id }) else { return (nil, nil) }
        return (index > 0 ? run[index - 1] : nil, index + 1 < run.count ? run[index + 1] : nil)
    }

    /// The text subtitle track get_subtitles reads, with the item's media source: `wanted`, else
    /// the one that plays, else the only text track.
    public static func subtitleTrack(of item: JFItem, wanted: Int?, playing: Int?) throws -> (sourceId: String, stream: JFMediaStream) {
        guard let source = item.mediaSources?.first, let sourceId = source.id else { throw ToolError("\(item.name) has no media file") }
        let subtitles = (source.mediaStreams ?? []).filter { $0.type == "Subtitle" }
        let text = subtitles.filter { $0.isTextSubtitleStream == true && $0.index != nil }
        guard !text.isEmpty else {
            throw ToolError(subtitles.isEmpty ? "\(item.name) has no subtitles." : "\(item.name) has only image subtitles (no text subtitles).")
        }
        let list = { () -> String in
            let data = (try? JSONSerialization.data(withJSONObject: text.map(trackJSON), options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
        if let wanted {
            guard let match = text.first(where: { $0.index == wanted }) else {
                throw ToolError("Track \(wanted) is not a text subtitle track of \(item.name). Text tracks: \(list())")
            }
            return (sourceId, match)
        }
        if let playing, let match = text.first(where: { $0.index == playing }) { return (sourceId, match) }
        if text.count == 1 { return (sourceId, text[0]) }
        throw ToolError("\(item.name) has \(text.count) text subtitle tracks; pass track with one of these indexes: \(list())")
    }

    /// list_episodes' answer from a series' ordered episodes: the seasons with counts, or one
    /// season's episodes.
    public static func episodesJSON(_ episodes: [JFItem], season: Int?, seriesName: String) throws -> [String: Any] {
        guard let season else {
            let seasons = Dictionary(grouping: episodes) { $0.parentIndexNumber ?? 0 }
            return ["seasons": seasons.keys.sorted().map { number -> [String: Any] in
                let list = seasons[number] ?? []
                return ["season": number, "episodes": list.count, "played": list.filter { $0.userData?.played == true }.count]
            }]
        }
        let list = episodes.filter { $0.parentIndexNumber == season }
        guard !list.isEmpty else { throw ToolError("No season \(season) in \(seriesName)") }
        return ["season": season, "episodes": list.map { episode -> [String: Any] in
            var entry = jellyfinJSON(episode)
            entry["title"] = episode.name
            if let number = episode.indexNumber { entry["episode"] = number }
            entry["played"] = episode.userData?.played ?? false
            return entry
        }]
    }
}
