# Design

## Context

The player's `PlayerEngine` is a `@StateObject` of `PlayerScreen`; its `PlaybackProgress`
(`position`, `duration`, `liveStart`/`liveEnd`, `wallClock`, `followsLive`, `behindLive`) and
`status`/`isPaused` are only reachable from that view. Jellyfin playback through a transcode adds
`timelineOffset` to the position; `progress.position` already includes it. Runtimes:
`JFItem.runTimeTicks` and `userData.playbackPositionTicks` (Jellyfin), the resume store's
position/duration for IPTV films and episodes (`resume.<key>`, `resume.<key>.duration`), the
recording window for recordings, `get_vod_info`'s `duration` for IPTV films not yet started.

## Goals / Non-Goals

**Goals:**
- Exact progress from the engine, not estimates.
- Runtimes wherever the source has them, without new requests where the data is already loaded.

**Non-Goals:**
- Player control beyond play/stop.

## Decisions

- **`AppModel.playerEngine` (weak)**, set by `PlayerScreen` on appear and cleared on disappear.
  `now_playing` reads `progress`, `status`, `isPaused`. Rejected: publishing progress into
  `AppModel` (10 Hz updates would re-render the whole library) and moving the engine out of the
  view (large refactor for a read-only need).
- **Units**: seconds as numbers (`position_seconds`, `duration_seconds`,
  `remaining_seconds`) plus `"h:mm:ss"` strings and `ends_at` (ISO 8601) so assistants need no
  arithmetic. Live: `follows_live`, `behind_live_seconds`, `show` (title, start, end) and no
  remaining for the stream itself (it has none); the show's end gives "how long".
- **`item_info(item_id)`**: `jellyfin:` → `JellyfinStore.call { item(userId:id:) }` (one request);
  `movie:` → catalog entry + `movieDetails` (one request) for plot/duration; `episode:` →
  `seriesInfo` (one request, cached per call); `recording:` → the recording window and file.
  Remaining from the resume position where one exists. Adult/visibility and the films/series
  switches apply as in `play`.
- **No change to the Jellyfin write path**: everything here is read-only.

## Risks / Trade-offs

- [Jellyfin cannot be tested against the user's server from debug builds] → the engine path is
  the same for every source and is tested with an IPTV film and a recording on the demo server;
  the Jellyfin fields are checked read-only through MCP against the user's installed nightly
  (`now_playing` while they play an episode, `recently_watched`, `item_info`).
- [No player window open] → `now_playing` reports what `nowPlaying` says without progress fields.
