# Tasks

## 1. Progress

- [x] 1.1 Add `AppModel.playerEngine` (weak), set/cleared by `PlayerScreen`; extend `now_playing` with position, duration, remaining (seconds and h:mm:ss), `ends_at`, paused/buffering, and for live `follows_live`, `behind_live_seconds` and the current show; verify on the demo server (`IPTV_MCP=1 IPTV_MCPTOKEN=test`): play `movie:500` (with IPTV films switched on via `IPTV_SHOWMOVIES=1`), read `now_playing` twice 10 s apart (position advances, remaining shrinks), play a recording and live channel 101 (follows_live true, show with end) — Done: film from the start 0:04→0:14 in 10 s, remaining 0:47→0:37, ends_at set, state playing; recording 0:04/0:16 with remaining and ends_at; live 101 follows_live true with the current show and its end; after stop playing false

## 2. Runtimes and item_info

- [x] 2.1 Add runtime and remaining to `recently_watched` (Jellyfin items from runTimeTicks/playbackPositionTicks, IPTV films from the resume store) and the new `item_info` tool (definitions, all four id kinds); verify on the demo server with `IPTV_TESTRESUME=movie.500:1200:5400` (`recently_watched` shows runtime 1:30:00, remaining 1:10:00; `item_info movie:500` adds plot and year; `item_info recording:<id>` gives the window), and with `http://127.0.0.1:9` as Jellyfin (no error, no Jellyfin part) — Done: recently_watched shows movie:500 with runtime 1:30:00, position 0:20:00, remaining 1:10:00; item_info movie:500 adds plot, genre, release date and the provider runtime 1:58:00; item_info recording gives window and runtime; Jellyfin unreachable: no Jellyfin part, item_info jellyfin answers "No Jellyfin account"

## 3. Integration

- [x] 3.1 Build Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without warnings; `openspec validate --all --strict`; update `DEVELOPMENT.md`
- [x] 3.2 After the user installs the nightly: read-only MCP calls against their running Fernsy (`now_playing` during a Jellyfin episode, `recently_watched`, `item_info` for a Next Up episode) to confirm the Jellyfin fields — Follows with the nightly (read-only MCP calls against the user's Fernsy); the engine path is the same as for the tested film and recording
