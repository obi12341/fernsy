# Proposal

## Why

An assistant could not continue a Jellyfin series after an episode ended. It had no way to find
the next episode's id: `item_info` gives only the season and episode number, and there is no
episode list. Next Up still showed the old episode, because Fernsy reports the end to Jellyfin
only when the player closes or the next episode starts. Fernsy's own countdown then started the
next episode 10 seconds later, but `now_playing` did not say so, and the assistant gave up and
asked the user to start it by hand.

## What Changes

- When a Jellyfin item ends, Fernsy reports the stop with the end position to the server at once
  (so Jellyfin marks it played and Next Up moves on) and reloads its Continue Watching / Next Up
  lists. Closing the player afterwards does not report again.
- `now_playing` reports, while the end-of-episode countdown runs, the next episode
  (`item_id`, title, season/episode) and the seconds until it starts. If the user cancelled the
  countdown, it reports that instead.
- `item_info` for Jellyfin episodes adds `previous_item_id` and `next_item_id` (with their
  season/episode numbers and titles), across season boundaries.
- New MCP tool `list_episodes` for Jellyfin series: the seasons of a series, or the episodes of
  one season, with item ids, numbers, titles, runtime and watched / in-progress state.

### Out of scope

- IPTV series: `list_episodes` and the neighbour ids are Jellyfin only (IPTV series are switched
  off for this user, and `play episode:<series>:<episode>` stays as it is).
- A `play_next` tool. `next_item_id` plus `play` covers it in one step.
- Changes to the countdown itself (length, buttons) and to resume handling inside Fernsy.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `jellyfin-playback`: the end of an item is reported to the server immediately, not only when
  the player closes.
- `mcp-server`: `now_playing` shows the upcoming next episode, `item_info` gives episode
  neighbours, new `list_episodes`.

## Impact

- `Fernsy/Jellyfin/JellyfinPlayback.swift`: report on `.ended`, guard against a second stop
  report, and own the next-episode countdown (deadline / cancelled) so the overlay and MCP share
  it.
- `Fernsy/Views/PlayerScreen.swift`: `NextEpisodeOverlay` reads the countdown from the playback
  object, and the playback object becomes reachable for MCP (like `AppModel.playerEngine`).
- `Fernsy/Jellyfin/JellyfinClient.swift`: adjacent-episode query; reuse `seasons`/`episodes`.
- `Fernsy/MCP/MCPTools.swift`: `now_playing`, `item_info`, `list_episodes` (definition, handler).
- `DEVELOPMENT.md` (MCP tools). Users of the Claude Desktop extension reinstall it to see
  `list_episodes`.
