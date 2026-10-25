# Tasks

## 1. Tracks and choice

- [x] 1.1 Local test Jellyfin again (Docker, 127.0.0.1 only) with a test film that has a forced German SRT, a full German SRT and an embedded English track, plus a film with one text track; the debug build signs in with `JF_SERVER`/`JF_USER`/`JF_PASS` against it only; verify the tracks show in Jellyfin's API
- [x] 1.2 `item_info` lists audio and subtitle tracks with `index`, `language`, `title`, `forced`, `default`, `external`, `text`; verify on the test film (forced flag only on the forced track)
- [x] 1.3 `get_subtitles` with `track` instead of `language`; without it the playing text track, else the only text track, else an error listing the text tracks; wrong index gives the list; verify with the debug build (`IPTV_MCP=1 IPTV_MCPTOKEN=test`): full German by index, the error without `track`, the single-track film without `track`, and the playing track while the film plays with a subtitle chosen

## 2. Timeout

- [x] 2.1 `subtitleSRT` with a 120 s request timeout, the timeout error worded as "preparing, try again"; verify through a local delaying proxy in front of the test Jellyfin (subtitle requests held 30 s): `get_subtitles` returns the cues after ~30 s, and with a 130 s hold the answer is the retry message

## 3. Integration

- [x] 3.1 `DEVELOPMENT.md` and the tool descriptions updated; Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) build without warnings; `openspec validate --all --strict`
