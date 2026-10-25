# Design

## Context

`PlayerEngine` already implements everything the app's controls use: `setPaused(_:)`,
`seek(to:)` (clamped to the timeshift buffer, or to the file length; a Jellyfin transcode
restarts through `external.restartAt`), `seek(by:)` and `goLive()`. `PlaybackProgress` publishes
`liveStart`/`liveEnd` (buffer range on the media timeline), `position`, `wallClock` (clock time of
`position`), `followsLive` and `behindLive`. MCP reaches the engine through
`AppModel.playerEngine`.

## Goals / Non-Goals

**Goals:**
- MCP control with exactly the app's semantics and limits.

**Non-Goals:**
- New player behaviour.

## Decisions

- **Tools call the engine's existing functions** on the main actor; no new engine API.
  `pause`/`resume` → `setPaused`; `seek.by_seconds` → `seek(by:)`; `to_position` → `seek(to:)`
  (accepts seconds or "h:mm:ss"/"m:ss"); `to_live` → `goLive()`; `to_time` and `to_show_start` →
  `seek(by: target − wallClock)` using the clock time of the current position, so no inverse
  lookup in the buffer is needed. Exactly one target per call; anything else is an error.
- **Clamping is reported, not refused**: after the seek the answer compares the requested and the
  resulting position (more than 2 s apart → `limited: true` with the reason "buffer starts at …"
  or "file ends at …").
- **Live without timeshift** (channel played directly because its streams cannot be buffered):
  `seek` answers that this channel cannot be rewound; pause works as the app's does.
- **`now_playing` live fields**: `rewind_available_seconds` = position − liveStart,
  `buffer_starts_at` = wallClock − rewind, `buffer_seconds` = liveEnd − liveStart,
  `buffer_limit_minutes` (the Settings value), `show_start_in_buffer` (show start ≥ buffer start).
- **The answer is `now_playing` after a short settle** (up to 1.5 s, until the engine leaves
  `buffering`), so the assistant sees the new position.

## Risks / Trade-offs

- [The user is watching while the assistant seeks] → that is the purpose; every control call is
  logged under `mcp` with the client name.
- [Seeking a Jellyfin transcode takes seconds] → the answer says `buffering`; a later
  `now_playing` shows the result.
