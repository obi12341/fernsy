# Proposal

## Why

Over MCP an assistant can start and stop playback and read the position, but it cannot pause,
resume or seek, and for live TV it cannot tell how far back the current channel can be rewound.
"Pause for a minute", "jump back 30 seconds", "go back to the start of the show" or "how far can
I rewind?" all need the player itself.

## What Changes

- New MCP tools `pause` and `resume` for whatever plays (live TV keeps receiving while paused, as
  in the app).
- New MCP tool `seek` with exactly one of: `by_seconds` (relative, ±), `to_position` (seconds or
  "h:mm:ss" for films, episodes, Jellyfin and recordings), `to_time` (a clock time within the
  live buffer), `to_show_start` (the start of the current show, as far as the buffer reaches) or
  `to_live` (back to the live edge). The player's own limits apply (buffer range, file length);
  a request beyond them is clamped and the answer says so. A Jellyfin transcode restarts at the
  new position as it does in the app.
- `now_playing` for live TV adds the timeshift range: how many seconds can be rewound from the
  current position, the clock time the buffer reaches back to, the buffer length and the
  configured maximum; plus whether the current show's start is still in the buffer.
- The answer of every control call is the new `now_playing`.

Out of scope:
- Volume, audio/subtitle tracks, full screen, picture in picture over MCP.
- Rewinding a channel that is not the one playing (only the tuned channel has a buffer).
- Siri for these actions (no schema; MCP only, as decided for Siri).

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `mcp-server`: new requirement "Player control through the assistant" (pause, resume, seek,
  timeshift range in `now_playing`).

## Impact

- `Fernsy/MCP/MCPTools.swift` (three tools, `now_playing` live fields) using
  `AppModel.playerEngine` (`setPaused`, `seek(to:)`, `seek(by:)`, `goLive`, `progress`).
- `DEVELOPMENT.md`.
