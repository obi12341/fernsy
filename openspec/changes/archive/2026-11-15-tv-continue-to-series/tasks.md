# Tasks

## 1. Series lookup and menu

- [x] 1.1 Add `DetailTarget.series(for:)` in `FernsyTV/Model/TVModel+Search.swift` (design 2): IPTV episode → `.series`, Jellyfin episode → `.jellyfin(series item)` from `jellyfin.series` or `loadDetail(seriesId)`, nil when not found; use it in Start's `info(_:)` instead of the fallback to the episode. Verify the tvOS app builds and the existing `StartUITests` pass on the host (`scripts/tv-uitest.sh "-only-testing:Fernsy TV UITests/StartUITests"`, demo server).
- [x] 1.2 Add the shared menu (design 3) to Start's "Weiterschauen" and "Nächste Folge" rows and to both rows on Jellyfin's Übersicht: "Fortsetzen"/"Abspielen", "Von Anfang an" (progress), "Zur Serie" (episode) or "Details" (film); "Zur Serie" in German "Zur Serie" in `FernsyTV/Localizable.xcstrings`. Give `JellyfinScreen` a `NavigationPath` (design 4). Verify the tvOS and iOS apps build.

## 2. Back to the series

- [x] 2.1 Open the series page of an episode played from these rows and from Start's large entry once the player has closed (design 1 as changed in "Notes from implementing": pushed on the cover's dismissal), not when it is already on top. Verify the tvOS app builds and `BackUITests`, `VODSwitchUITests` and `StartUITests` pass on the host.

## 3. Tests

- [x] 3.1 Add `ContinueToSeriesUITests` to `FernsyTVUITests` (demo server, an IPTV episode started via `IPTV_TESTRESUME=episode.00101:300:2760`, as `LibraryUITests`): (a) long press on the episode in "Weiterschauen" → "Zur Serie" opens its series page, Back returns to Start; (b) click plays it, Back until playback stops shows the series page, Back again shows Start; (c) a film from "Weiterschauen" (`IPTV_TESTRESUME` with a demo film key) stopped returns to Start; (d) "Von Anfang an" on the film plays from 0 (debug MCP `now_playing` position). Verify on the host, and that (a) and (b) fail with the menu item and the push removed.
- [x] 3.2 Jellyfin (needs the local test Jellyfin, `scripts/jellyfin-test-server.sh`, skipped without it as `JellyfinEdgesUITests`): a partly watched Jellyfin episode in Start's "Weiterschauen" gets the menu with "Zur Serie" opening the Jellyfin series page; on Übersicht, "Nächste Folge" offers "Abspielen" and "Zur Serie" without "Von Anfang an", and Back after playing lands on the series page, then Übersicht. Verify on the host with the test server running.
- [x] 3.3 Run all Apple TV UI tests on the host and `openspec validate --all --strict`. Verify all pass, apart from failures that also fail on `main`, named in design.md. Attach a German screenshot of the menu (`-AppleLanguages (de)`) for the user.

## Workflow follow-up

- Archive on `change/tv-continue-to-series` after the checks, then merge into `main` and push when the user agrees.
- The user-visible commit carries `Release-Note-de` / `Release-Note-en` trailers (long press on Weiterschauen/Nächste Folge leads to the series; Back after an episode lands on its series).
