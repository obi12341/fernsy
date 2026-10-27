# Tasks

## 1. Shared code

- [x] 1.1 Jellyfin client and store into `FernsyCore`, Jellyfin playback into `FernsyPlayer`, the search index and the IPTV film/series state into `FernsyCore` (design A), with tests. Verify: `scripts/test.sh --tvos-sim` passes; Mac regression on the Docker Jellyfin (127.0.0.1:8097): play, resume, progress on the server, next-episode countdown; Mac search finds channels, films and series as before; Debug, Direct and Release with 0 warnings.
- [x] 1.2 Device identity per design B. Verify: after an Apple TV debug sign-in the Docker Jellyfin's devices list shows the Apple TV debug device next to the Mac's, and the Mac's session stays signed in.

## 2. Navigation and sign-in

- [x] 2.1 Tabs Start, Filme, Serien, Jellyfin and search, hidden without their source; the app opens on Start. Verify: screenshots with the demo account, with only the Docker Jellyfin, and with both.
- [x] 2.2 Jellyfin card on the welcome screen, Jellyfin form, Settings › Konto hinzufügen. Verify: sign-in to the Docker Jellyfin from the welcome screen and from Settings; a wrong password keeps the form with the message.

## 3. Library screens

- [x] 3.1 Start per design C (screen `home`). Verify: Start shows an IPTV film and a Jellyfin film in "Weiterschauen" with their source, newest first, the newest as the large entry; screenshot next to the design. The demo films are under a minute and the fixture episodes two minutes, so playing them marks them watched instead of keeping a position (Mac rule: last 90 s; Jellyfin: under 5 minutes): the IPTV entry comes from `IPTV_TESTRESUME`, the Jellyfin one from playing the 8-minute fixture film; saving positions is covered by `LibraryStateTests`.
- [x] 3.2 Filme and Serien grids with category picker and sorting, image pipeline (design E, screen `filme`). Verify: demo-server screenshots; "Bewertung" orders by rating; scrolling the grid does not reload posters (log).
- [x] 3.3 Film page (screen `film`) with Fortsetzen, Von vorn and favourite. Verify: a demo film resumes at the stored position; "Von vorn" starts at 0.
- [x] 3.4 Series page (screen `serie`) with seasons, episodes, "Nächste Episode" and "Als Nächstes". Verify: a demo series and a fixture series show the next episode as in the scenario.
- [x] 3.5 Jellyfin tab (screen `jellyfin`) with Übersicht, Filme, Serien, Bibliotheken, unwatched counts and the not-reachable state. Verify: Docker Jellyfin screenshots; stopping the container shows the cached lists with the message.

## 4. Search and playback

- [x] 4.1 Search per design D (screen `suche`). Verify: typing "kart" on the demo server shows live TV and film results; a hidden channel's shows are not found; clicking a running show plays its channel.
- [x] 4.2 On-demand playback on Apple TV: resume, tracks, next-episode countdown, Jellyfin reporting, IPTV watched at the end. Verify: MCP `play_item` and `now_playing` on 52325; the Docker Jellyfin's resume position after stopping; an IPTV demo episode played to its end shows "Gesehen".

## 5. Checks

- [x] 5.1 UI tests: from Start into a film page and play; search for a film and open it. `scripts/tv-uitest.sh` passes; German and English strings complete (LocalizationTests).
- [x] 5.2 `openspec validate --all --strict` exits 0; Mac Debug, Direct ("Fernsy Direct") and Release and the Apple TV Debug build have 0 warnings; `scripts/test.sh --tvos-sim` passes; the Docker Jellyfin container is removed.

## Workflow follow-up

- Starts after `tvos-live` is archived (this delta modifies its Navigation and sign-in requirements).
- No Release-Note trailers while the Apple TV app is not shipped.
- DEVELOPMENT.md › Apple TV: screen slots, MCP `play_item`, the Jellyfin device id on Apple TV.
