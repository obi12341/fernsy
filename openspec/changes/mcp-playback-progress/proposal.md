# Proposal

## Why

Asked through MCP, Fernsy says what plays but not where: `now_playing` has no position, no
duration and no remaining time, so "how long until the episode ends?" cannot be answered while a
Jellyfin title (or an IPTV film, episode or recording) plays. The history tools also leave out
runtimes, so an assistant cannot say how long the next episodes or the films in "Continue
Watching" are, or how much of them is left.

## What Changes

- `now_playing` reports, for anything that plays: position, duration and remaining time (seconds
  and as "h:mm:ss"), whether it is paused or buffering, and the clock time it will end at
  (now + remaining). For live TV: whether it follows live or how far behind live it is, plus the
  current show with its end time.
- `recently_watched` adds runtime and remaining time to each Jellyfin item (Continue Watching,
  Next Up) and each IPTV film in progress.
- New tool `item_info(item_id)`: title, type, runtime, remaining (from the resume position),
  plot, year and, for episodes, series/season/episode, for `movie:`, `episode:`, `jellyfin:` and
  `recording:` ids.

Out of scope:
- Seeking, pausing or other player control over MCP.
- Listing a Jellyfin series' seasons and episodes (only the items the tools already return, and
  `item_info` for any id).

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `mcp-server`: "Guide and history tools" adds runtimes and the `item_info` tool; "Playback
  through the assistant" makes `now_playing` report progress.

## Impact

- `Fernsy/MCP/MCPTools.swift` (now_playing, recently_watched, item_info, definitions).
- `AppModel`: a weak reference to the player's `PlayerEngine` (set by `PlayerScreen`), so the
  position is readable outside the view.
- `DEVELOPMENT.md`.
