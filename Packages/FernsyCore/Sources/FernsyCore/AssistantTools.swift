import Foundation

/// The tools Fernsy offers to language models: the Mac's MCP server (Claude Desktop) and the
/// in-app assistant use the same names, descriptions and schemas (cloud-assistant design 4).
/// The Mac runs every tool; the Apple TV and iOS apps run the ones the assistant offers and
/// their platform supports. `scripts/assistant-tools.sh` exports the assistant's set for the
/// Fernsy Cloud worker, which attaches it to every relayed request.
public enum AssistantTools {
    /// At most this many channels per guide query.
    public static let channelLimit = 50

    /// All tools in MCP form (`inputSchema`, annotations).
    public static var definitions: [[String: Any]] {
        [
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
            tool("play", "Play an item in Fernsy's player: live:<channel id> (switches channels), movie:<id>, episode:<series id>:<episode id>, jellyfin:<item id>, recording:<id> or cloud:<Fernsy Cloud id>. Never ends a running recording.", [
                "item_id": ["type": "string"],
            ], required: ["item_id"], readOnly: false),
            tool("now_playing", "What Fernsy's player plays right now, with position, duration, remaining time, end time and paused state; for live TV how far behind live and the current show.", [:], readOnly: true),
            tool("item_info", "Details of a film, episode, Jellyfin item or recording: title, runtime, remaining time, plot, year, series/season/episode; for Jellyfin items the audio and subtitle tracks, and for episodes the previous and next episode.", [
                "item_id": ["type": "string", "description": "movie:<id>, episode:<series id>:<episode id>, jellyfin:<item id>, recording:<id> or cloud:<id>"],
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
            tool("get_subtitles", "The text subtitles of a Jellyfin item with start and end times, for finding a scene by what is said. Choose the track from item_info's subtitle_tracks (forced tracks only cover foreign-language parts).", [
                "item_id": ["type": "string", "description": "jellyfin:<id>; default: the Jellyfin item that plays"],
                "track": ["type": "integer", "description": "Subtitle track index from item_info's subtitle_tracks; default: the track that plays, or the only text track"],
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
    }

    /// The tools the in-app assistant offers: watching, finding and recording. Not the
    /// diagnostics (log, playback statistics) or the image tools (snapshot, frames), which cost
    /// many tokens and help a support conversation more than a viewer.
    public static let assistantNames: [String] = [
        "find_channels", "whats_on", "get_program", "search_program", "recently_watched", "list_recordings",
        "schedule_recording", "cancel_recording", "play", "now_playing", "item_info", "list_episodes",
        "stop_playback", "pause", "resume", "seek", "get_subtitles",
    ]

    /// The assistant's tools in the chat completions form OpenRouter takes (`type: function`,
    /// `parameters`), in `assistantNames` order.
    public static var assistantDefinitions: [[String: Any]] {
        let byName = Dictionary(uniqueKeysWithValues: definitions.compactMap { tool in (tool["name"] as? String).map { ($0, tool) } })
        return assistantNames.compactMap { name in
            byName[name].map {
                ["type": "function",
                 "function": ["name": name, "description": $0["description"] ?? "", "parameters": $0["inputSchema"] ?? [:]]]
            }
        }
    }

    /// `assistantDefinitions` as the worker's module `assistant-tools.js` (stable JSON with sorted
    /// keys behind `export default`), so the worker and its Node tests import it alike.
    public static func workerModule() throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: assistantDefinitions, options: [.prettyPrinted, .sortedKeys])
        let header = "// Generated by scripts/assistant-tools.sh from FernsyCore AssistantTools. Do not edit.\nexport default "
        return Data(header.utf8) + json + Data(";\n".utf8)
    }

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String] = [], readOnly: Bool) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties, "additionalProperties": false]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": description, "inputSchema": schema,
                "annotations": ["readOnlyHint": readOnly, "destructiveHint": false, "openWorldHint": false]]
    }
}
