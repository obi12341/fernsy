# Tasks

## 1. Test server

- [x] 1.1 Local test Jellyfin in Docker (`jellyfin/jellyfin`, 127.0.0.1 only) with a generated series of 2 seasons × 3 episodes, 6 minutes each (the image's bundled ffmpeg, test pattern with a burned-in title), plus one special in season 0; the debug build signs in with `JF_SERVER`/`JF_USER`/`JF_PASS` against it only (never the user's server); verify the series and its episodes show in the library. If the `mcp-scene-search` change already created this server, extend it.

## 2. End report and countdown

- [x] 2.1 `JellyfinPlayback`: stop report with the duration on `.ended`, `endReported` guard in `stop()`, reset and new start report when playback continues after the end; `refreshAfterPlayback` on `.ended`; verify against the test Jellyfin (MCP `play` + `seek to_position 5:52`, since `JF_AUTOPLAY` waits for films and the test server has none) with `IPTV_MCP=1 IPTV_MCPTOKEN=test`: within 2 s after the end the server's `UserData.Played` of S1E1 is true and `/Shows/NextUp` lists S1E2 (read via the server API), and MCP `recently_watched` already shows S1E2 under next_up; closing the player afterwards sends no second stop (server log / request count)
- [x] 2.2 Seeking back after the end: after the end report, `seek to_position 60` via MCP continues playback, and the server shows a new play session and progress again; verify via the server's `/Sessions` API
- [x] 2.3 Countdown in `JellyfinPlayback` (`autoplayAt`, `autoplayCancelled`), overlay reads it, weak `AppModel.jellyfinPlayback`; `now_playing` reports `next` with `starts_in_seconds`; verify on the test Jellyfin: `now_playing` 3 s after the end shows about 7 s and the S1E2 item id, S1E2 starts after the countdown, and after cancelling (debug switch or the overlay's cancel via a test hook) `now_playing` shows `next` without a start time

## 3. Episode tools

- [x] 3.1 `item_info` for Jellyfin episodes adds previous/next (`*_item_id`, season, episode, title) from the whole series list, skipping season 0 unless the item is a special; verify on the test series: S1E1 (next only), S1E3 (next is S2E1), S2E3 (previous only), the special
- [x] 3.2 `list_episodes` (definition, handler; series id or episode id; seasons without `season`, episodes with it including played/in-progress state; error for non-Jellyfin ids); verify on the test series: seasons with counts, season 2 with ids, then `play` with S2E2's id plays it, and an IPTV `episode:` id on the demo server gives the error

## 4. Integration

- [x] 4.1 `DEVELOPMENT.md` lists `list_episodes` and the new `now_playing`/`item_info` fields; verify the generated `.mcpb` manifest lists `list_episodes` (mcpb harness)
- [x] 4.2 End-to-end: through the test client, play S1E3, seek to its end, call `now_playing`, then `play` the `next` item id before the countdown ends, and check that S2E1 plays and the server shows S1E3 as played
- [x] 4.3 Build Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without warnings; `openspec validate --all --strict`

## Workflow follow-up

- After the nightly is installed and the desktop extension reinstalled: the user asks Claude to continue a series after an episode; read-only check of `item_info` neighbours on the user's own Jellyfin via the release MCP server (port 52323).
