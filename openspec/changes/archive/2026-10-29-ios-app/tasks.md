# Tasks

## 1. Foundation

- [x] 1.1 Add `ios` and `iossim` slices to `scripts/build-ffmpeg.sh` and rebuild FFmpeg. Verify that each `Packages/FernsyPlayer/Frameworks/*.xcframework` lists ios-arm64 and ios-arm64-simulator, and that the script still refuses GPL/nonfree.
- [x] 1.2 Add `.iOS("27.0")` to FernsyCore and FernsyPlayer, and fix what fails to compile for iOS (platform conditionals only, no behaviour change on macOS/tvOS). Verify that `xcodebuild` builds both packages for the iOS simulator, and that the Mac and Apple TV targets still build.
- [x] 1.3 Create the target "Fernsy iOS" (folder `FernsyiOS/`, iPhone + iPad, iOS 27, bundle id `de.mobilistics.fernsy`, Debug `.dev`/"Fernsy Dev", entitlements for keychain and iCloud key-value store, background mode audio, all orientations, own `Assets.xcassets` with app icon, `InfoPlist.xcstrings`). Share `FernsyTV/Model`, `Support`, `Player`, `Debug` and `Localizable.xcstrings` through the synchronized group with an exception set. Verify that the target builds for the iOS simulator and that the Apple TV target is unchanged (still builds).
- [x] 1.4 Make the shared files compile on iOS with `#if os(...)` (focus APIs in `PlayerStatusLayer`, tvOS-only APIs); no record UI on iOS (design 7). Verify that both targets build.
- [x] 1.5 Write `scripts/ios-run.sh` (build, boot an iPhone simulator with its window, install, launch with `SIMCTL_CHILD_*` demo defaults, log file) and document it in `DEVELOPMENT.md`. Use debug MCP port 52326. Verify with `scripts/ios-run.sh` that the app launches in the simulator and logs its start.

## 2. Sign-in and navigation

- [x] 2.1 Root screen: iCloud sign-in state, the welcome screen with the IPTV and Jellyfin cards, and the sign-in forms (autofill, "Demo-Zugang testen", error text) on `TVModel`. Verify on the demo server (`scripts/ios-run.sh` with an empty account) that "Demo-Zugang testen" signs in, using a simulator screenshot.
- [x] 2.2 Tab navigation with `TabView` + `.sidebarAdaptable` (Start, Live TV, Filme, Serien, Jellyfin, Suche, Einstellungen), with tabs hidden by account and switches. Verify with screenshots on an iPhone and an iPad simulator with the demo account (no Jellyfin tab).

## 3. Live TV and the live player

- [x] 3.1 Live TV Liste: source picker (Favoriten, Zuletzt gesehen, Alle Sender, pinned, Alle Kategorien), channel rows with now/progress/next, a context menu (favourite, hide), and the iPad landscape pane. Source and view are kept. Verify with screenshots and a favourite toggle on the demo server.
- [x] 3.2 Alle Kategorien: tiles or rows, country chips, search, pin/unpin/hide. Verify that filtering by a demo country chip narrows the list.
- [x] 3.3 Live player: full-screen cover, landscape on iPhone, video surface, tap-to-show controls with auto-hide, play/pause, ±skip, draggable timeshift timeline with "−mm:ss", Live, tracks, close and swipe down, status/stall/failure cards, technical panel. Verify with `IPTV_AUTOPLAY=live:101` in the simulator: picture shows, pause and back-in-buffer work through the debug MCP (seek), with screenshots.
- [x] 3.4 Channel list in the player and vertical swipe zapping, with the Mac's tuning rules. Verify zapping between two demo channels through the debug MCP or a synthetic tap, and check the log for the tuner switch.

## 4. Program guide

- [x] 4.1 Programm view: a two-way scrolling grid with a sticky channel column, the now line, dimmed past and highlighted running shows, bars for missing, loading or gap listings, tap to play or show details. Verify with a screenshot of the demo guide and by tapping a running show.

## 5. Start, films and series, on-demand playback

- [x] 5.1 Start: large entry and the rows (without recordings), sideways scrolling, tap to play or open. Verify with a screenshot on the demo account.
- [x] 5.2 Filme and Serien grids (adaptive columns, category picker, sorting), the film page and the series page (seasons, next episode). Verify sorting by rating and the series page on demo content.
- [x] 5.3 On-demand player: resume, tracks, timeline with time left, skip, next-episode countdown, IPTV episode watched at the end. Verify with `IPTV_AUTOPLAY=movie:500` that the demo film plays and resumes after closing and reopening.

## 6. Jellyfin, search, settings

- [x] 6.1 Jellyfin tab (Übersicht, Filme, Serien, Bibliotheken) on the shared model, with its own device name and id. Verify by building. A live check against a Jellyfin server waits until the other agent's test container is free (do not use it while its test round runs).
- [x] 6.2 Suche with the system search field and the results (live now/later, IPTV, Jellyfin with source). Verify by searching the demo catalog for a known title.
- [x] 6.3 Einstellungen: accounts with sign-out, Konto hinzufügen, Filme/Serien switches, Wiedergabe with Technische Infos, iCloud, Protokoll, version. Verify that switching Filme off removes the Filme tab in the simulator.

## 7. Picture in Picture and AirPlay

- [ ] 7.1 (Deferred to a follow-up change: v1 ships screen mirroring, design 6) Spike: move the engine's display layer into an external-display window scene and back without a restart, and find how the route picker starts it. Record the result in design.md (decision 6). If it fails, fall back to plain mirroring and adjust the spec scenario.
- [x] 7.2 Picture in Picture: port the Mac controller, audio session `.playback`, automatic start when leaving, restore and close. `appWillLeave` keeps playback during PiP. Implemented and built. The simulator does not support PiP (`isPictureInPictureSupported()` is false there), so it was verified on the user's iPad (Release build, 2026-10-29): PiP works.
- [x] 7.3 AirPlay: route picker in both players (done, builds). The external-display scene waits for 7.1; until then iOS mirrors the player (design 6). Verified on the user's iPad (2026-10-29): AirPlay works.

## 8. Integration

- [x] 8.1 German translations for all new strings in the shared catalog and `InfoPlist.xcstrings`. Verify that the catalog has no untranslated iOS strings and the app shows German with a German simulator locale.
- [x] 8.2 CI: build the iOS target for the simulator in `tests.yml` and gate nightlies and releases on it (distribution requirement). Verify the workflow syntax with `actionlint` or a dry review, and that a local `xcodebuild` with the same command passes.
- [x] 8.3 Check that the Mac app and the Apple TV app still build and run unchanged: `scripts/dev-run.sh` plays a demo channel, and `scripts/tv-run.sh --no-build` is not run while the other agent's tvOS test round is active (build only).
- [x] 8.5 UI tests with real touch input (`scripts/ios-uitest.sh`, target "Fernsy iOS UITests"): the welcome screen signs in to the demo, a channel row plays and swipe down closes, the timeline goes back and LIVE returns, the channel panel zaps, swiping left zaps, the film page plays, the search finds a film. Verify that all pass on the iPhone 18 Pro and the iPad Pro 13-inch simulators.
- [x] 8.4 Run `openspec validate --all --strict`.

## Workflow follow-up

- User checks on a real iPhone/iPad: PiP when leaving the app, AirPlay to a speaker and to an Apple TV, the landscape player, and performance with the real catalog.
- App Store Connect: add the iOS platform to the record. TestFlight comes with the release workflow upload, which is a follow-up.
- Commit, archive and merge only after the user's review.
