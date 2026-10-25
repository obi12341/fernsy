# Design

## Context

See proposal.md for why. Current state:

- **Reporting.** `JellyfinPlayback` reports start when the engine first plays, progress every
  10 s and on pause, and stop only in `stop()`. `stop()` is called when the player closes or
  another item starts, with the full duration when the engine status is `.ended`. Afterwards it
  calls `store.refreshAfterPlayback`, which reloads the item and the Continue Watching / Next Up
  lists. `recently_watched` reads these cached lists.
- **Countdown.** `JellyfinPlayback.nextEpisode` is loaded at start (`client.nextEpisode`,
  `Shows/{series}/Episodes?startItemId=…&limit=2`). The countdown (10 s, cancel button) lives
  only in the SwiftUI state of `NextEpisodeOverlay` in `PlayerScreen`.
- **MCP access.** `PlayerScreen` owns the `JellyfinPlayback` (`@State`). MCP reaches the engine
  through the weak `AppModel.playerEngine` (set by `PlayerScreen`), not the playback object.
  `now_playing` already reports `state: "ended"`.
- **Jellyfin client.** `seasons(userId:seriesId:)` and `episodes(userId:seriesId:seasonId:)`
  exist for the series views.

## Goals / Non-Goals

**Goals:**
- Jellyfin knows an item ended at the moment it ends.
- One source of truth for the countdown, used by the overlay and by MCP.
- An assistant can continue, step back or jump to any episode of a Jellyfin series with ids it
  can get from the tools.

**Non-Goals:**
- IPTV series (see proposal).
- Prefetching or caching episode lists beyond what the series views already do.

## Decisions

- **Report the stop on `.ended`.** `JellyfinPlayback` observes the engine status. On `.ended` it
  sends the stop report with the duration as position, sets `endReported`, and starts
  `refreshAfterPlayback`. `stop()` skips its stop report when `endReported` is set (it still
  stops a transcode). If playback continues after the end (the user seeks back),
  `endReported` and `reportedStart` are reset so a new start report opens a fresh play session
  on the server before progress resumes. Rejected: marking the item played with
  `setPlayed` (it skips the server's own played logic and leaves the resume position
  untouched), and reporting progress at the end position (Jellyfin only updates played state
  and Next Up on a stop).

- **The countdown moves into `JellyfinPlayback`.** Published `autoplayAt: Date?` (set to
  now + 10 s on `.ended` when a next episode is known) and `autoplayCancelled`. The overlay
  shows the remaining seconds from `autoplayAt` and, as now, starts the next episode when it
  reaches zero. The cancel button sets `autoplayCancelled`. Rejected: having MCP compute the
  countdown from the end time (it would diverge from the overlay once the user cancels).

- **MCP reaches the playback through a weak `AppModel.jellyfinPlayback`**, set and cleared by
  `PlayerScreen` next to `playerEngine`. `now_playing` adds `next: {item_id, title, season,
  episode, starts_in_seconds?}` when the state is ended and a next episode is known.
  `starts_in_seconds` is omitted when cancelled.

- **Neighbours from the whole series list.** `item_info` loads the series' episodes once
  (`Shows/{series}/Episodes` without a season), sorts them by season and episode number and takes
  the entries before and after the item. Regular episodes skip season 0; a special's neighbours
  are the other specials. Rejected: `startItemId` (gives only the next episode) and `adjacentTo` (its
  behaviour with specials and missing episodes differs between server versions; the full list
  is one request and also serves `list_episodes`).

- **`list_episodes(series_id | item_id, season?)`.** An episode id resolves to its series. Without
  a season it returns the seasons (number, name, episode count). With one it returns the
  episodes: `item_id` (`jellyfin:<id>`), season, episode, title, runtime, `played`, and
  position/remaining when in progress. It uses the existing client calls, so the user data
  shown is the server's. Rejected: listing all episodes of all seasons by default (long series
  produce very large answers).

## Risks / Trade-offs

- [Stop report and the following start of the next episode race] → the next episode starts
  10 s later at the earliest, and the stop report is sent first. Each report goes through its
  own task, so they cannot block each other.
- [User seeks back after the end] → handled by the reset described above. Verified in the tasks.
- [Short test episodes and Jellyfin's minimum resume duration] → Jellyfin treats items shorter
  than its minimum resume duration differently. The test series uses episodes of 6 minutes so
  the "played" rule is the normal one.

## Open Questions

(none)
