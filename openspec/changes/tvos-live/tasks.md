# Tasks

## 1. Shared code

- [x] 1.1 Favourites, recently watched channels, hidden categories and channels, adult detection and the zap order move from the Mac app into `FernsyCore`, plus the new pinned categories (design A), same stored keys and format, with tests. Verify: `scripts/test.sh --tvos-sim` passes; a Mac dev run (`scripts/dev-run.sh IPTV_AUTOPLAY=live:101`) shows the same favourites, hidden items and pins as before the move.
- [x] 1.2 The recorder moves into `FernsyPlayer` behind a platform protocol, the Mac keeps its AppKit parts (design B). Verify: Mac regression `IPTV_TESTRECORD=101:5:60:0:0` records and plays on the demo server; with `IPTV_MAXCONN=1` the stream-limit question appears as before; Debug, Direct and Release builds with 0 warnings.

## 2. Frame and sign-in

- [x] 2.1 Tab bar per design F (Live TV, Programm, Aufnahmen, gear), opens on Live TV. Verify: `scripts/tv-run.sh` and screenshots of each tab; Up reaches the tab bar, Back from a tab's top level goes to it.
- [x] 2.2 Welcome screen and IPTV form (screens `login`, `login2`) with the keychain and "Demo-Zugang testen" (design H). Verify: `scripts/tv-run.sh FERNSY_NO_KEYCHAIN=1` without `IPTV_SERVER` shows the welcome screen; the demo button signs in to the demo server; a wrong password (`demo`/`x`) keeps the form with the message.

## 3. Live TV

- [x] 3.1 Category column, channel rows and the pane with now and next (screen `live`). Verify: demo-server screenshot next to the rendered design screen; tags, star, progress and time left are shown.
- [ ] 3.2 Preview in the pane per design E, Play/Pause for sound. Verify: MCP `now_playing` on 52325 shows the previewed channel after focus rests; with `IPTV_MAXCONN=1` and a recording running (`IPTV_TESTRECORD=102:5:60:0:0`) the pane shows the logo and no second connection opens (log).
- [ ] 3.3 Long-press menu: Aufnehmen, Favorit, Ausblenden; favourites, history and hiding as on the Mac (task 1.1). Verify: UI test hides a channel and it is gone from the list, the guide and the zap strip.
- [ ] 3.4 "Alle Kategorien" with country chips, search, pin and hide (screen `kategorien`). Verify: demo-server screenshot; pinning a category adds it to the column.

## 4. Guide and player

- [ ] 4.1 Guide grid per design G (screen `guide`). Verify: demo-server screenshot; clicking a running show plays it; clicking a later show schedules it and marks it.
- [ ] 4.2 Player overlay with timeline, time behind live and the Info, Untertitel, Ton tabs (screen `player`). Verify: MCP `seek by_seconds:-754` shows "−12:34" in a screenshot; audio and subtitle choices switch tracks on a demo channel with several tracks.
- [ ] 4.3 Channel strip with Down and the Sender tab (screen `zap`). Verify: UI test zaps from the strip and `player.state` reaches `playing` on the new channel.

## 5. Recordings and settings

- [ ] 5.1 Recordings on Apple TV per designs C and D: record now, schedule, padding, idle timer, stop on background, missed state, Caches index, free-space check. Verify: `IPTV_TESTRECORD=101:2:60:0:0` records and plays back in the simulator; sending the app home during a recording keeps an incomplete recording; a schedule that ends while the app is not running shows as missed at the next `tv-run.sh`.
- [ ] 5.2 Aufnahmen tab (screen `aufnahmen`) with running, scheduled, finished and failed recordings, playing with resume and deleting. Verify: screenshot; a finished recording plays and resumes; deleting removes file and entry.
- [ ] 5.3 Settings (screen `einstellungen`) with accounts and sign-out, Konto hinzufügen, Wiedergabe, Aufnahmen padding, Protokoll and the version; no iCloud and no Jugendschutz rows. Verify: screenshot; changing the padding shows in the row and in a newly scheduled recording.
- [ ] 5.4 Debug MCP tools `record`, `list_recordings`, `cancel_recording` (design J). Verify: all three answer during a demo run on 52325.

## 6. Checks

- [ ] 6.1 UI tests per design J pass with `scripts/tv-uitest.sh`; German and English strings in `FernsyTV/Localizable.xcstrings` (LocalizationTests pass).
- [ ] 6.2 `openspec validate --all --strict` exits 0; Mac Debug, Direct ("Fernsy Direct") and Release and the Apple TV Debug build have 0 warnings; `scripts/test.sh --tvos-sim` passes.

## Workflow follow-up

- Starts after `tvos-foundation` is archived (its `apple-tv` main spec is the base of this delta).
- No Release-Note trailers while the Apple TV app is not shipped; Mac commits from task 1 carry none either (no behavior change).
- DEVELOPMENT.md › Apple TV: update the screen slots, the MCP tools and the recordings notes.
