# Tasks

## 1. What the picture is (FernsyPlayer)

- [x] 1.1 `DisplayFormat` and `DisplayModeRequest`: frame rate snapped to the standard rates within 0.5 %, no rate for 0 or above 120 fps, a range key from transfer function, primaries and Dolby Vision, `==` for "ask again?" (design 1, 2)
- [x] 1.2 `PlaybackSession` publishes the `DisplayFormat` on the first decoded frame: stream rate doubled while the deinterlacer runs at 2×, format description of the first pixel buffer or `DVDecoder`'s; `PlayerEngine` exposes it and clears it on stop
- [x] 1.3 Start gate in `PlayerEngine` that the preroll gate also waits for; open by default, so Mac and iOS start as before (design 4)
- [x] 1.4 Unit tests: snapping (23.976, 25.02 → 25, 0 and 240 fps), 1080i25 → 50 Hz, HDR10 and HLG keys, Dolby Vision mapped to HDR10 gives the HDR10 key, equal requests compare equal; the gate holds and releases the start (FernsyPlayer tests on the Mac)

## 2. Asking tvOS (FernsyTV)

- [x] 2.1 `DisplayModeController`: follows the engine's format, full screen versus preview (`previewing`), and the setting; sets `preferredDisplayCriteria` on the key window's `avDisplayManager` only when the request changes; logs "display mode: …" requests, "unchanged" and "released" (design 2)
- [x] 2.2 Release the request 2 s after the player closes unless another item starts; release at once when the setting is turned off (design 3)
- [x] 2.3 Hold the start for a new request: wait up to 300 ms for `isDisplayModeSwitchInProgress`, then until it ends, at most 5 s; never hold a running picture (preview going full screen) (design 4)
- [x] 2.4 Settings › Playback › Player: "Match Frame Rate and Dynamic Range" (`player.matchDisplayMode`, default on) with the note about "Match Content"; English and German strings in `FernsyTV/Localizable.xcstrings` (design 5)

## 3. Verification

- [x] 3.1 tvOS UI test on "Claude Apple TV" with the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, `IPTV_USER=demo`, `IPTV_PASS=demo`): the setting is on by default and toggles; playing a demo film full screen logs a display-mode request with its frame rate; the Live TV preview logs none; with the setting off no request is logged
- [x] 3.2 `scripts/test.sh` passes, `openspec validate --all --strict` passes
- [x] 3.3 On "Apple TV WZ" (Release build) with the user, "Match Content" on: a 24p film switches the TV to 24 Hz and back on close; a 50 Hz channel switches to 50 Hz and zapping to another 50 Hz channel does not switch; an HDR10 or Dolby Vision title switches to HDR; the film starts at its resume position after the switch; tune the 300 ms wait if the start is lost
- [x] 3.4 Note in design.md what the real Apple TV showed (switch times, the tuned wait)

## 4. One switch per account (decided after the first device test)

- [x] 4.1 Replace the single setting with `player.matchDisplayMode.iptv` (default off) and `player.matchDisplayMode.jellyfin` (default on); the controller picks the switch by the playing item's account: live, catch-up, films, series, recordings and cloud recordings → IPTV, Jellyfin items → Jellyfin (design 5)
- [x] 4.2 Move the row from Settings › Playback into Settings › IPTV Account and Settings › Jellyfin Server, with the note; strings in English and German
- [x] 4.3 Update `DisplayModeUITests` on "Claude Apple TV" with the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, `IPTV_USER=demo`, `IPTV_PASS=demo`): the IPTV row is off by default and a demo film logs no request; turned on, the film logs a request and the preview none; turned back off; `scripts/test.sh` and `openspec validate --all --strict` pass
- [x] 4.4 On "Apple TV WZ" (Release) with the user: zapping does not switch with the IPTV option off; a Jellyfin film switches Confirmed by the user on 2026-10-31.

## Workflow follow-up

- Archive the change on `change/tvos-match-content`, merge into `main` and push with the user's consent.
