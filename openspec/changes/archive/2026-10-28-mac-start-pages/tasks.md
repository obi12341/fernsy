# Tasks

## 1. Shared rules

- [x] 1.1 FernsyCore: `LibraryEntry`, `StartRecording` and `StartBuilder` (design 1) with the rules of `startRows()`, `continueWatching`, `recentlyAdded`, `tonight(on:)` and the live source; unit tests for each row's selection and order, empty rows left out.
- [x] 1.2 FernsyTV: Start uses `StartBuilder` (no visible change); `StartUITests`, `StartScrollingUITests`, `LivingHeroUITests` green.

## 2. Mac Start

- [x] 2.1 `LibrarySection.start` at the top of the sidebar, selected at launch, no category column; `IPTV_SECTION=start` (design 2).
- [x] 2.2 Generic paging carousel from `JellyfinCarousel`; Start's rows with the Mac's cards, clicks and context menus (design 3, 4); rows rebuilt from an input key (design 7).
- [x] 2.3 Large entry as a banner with "Resume"/"Play" and "Details"; Mac `LivingBackdrop` active on hover, Reduce Motion, `IPTV_TESTHOVER=1` (design 5).

## 3. Mac Übersicht

- [x] 3.1 `.jellyfinHome` titled "Overview"/"Übersicht" with the spotlight banner, "Another Suggestion", the overview rows, numbers and tiles (design 6).
- [x] 3.2 `JellyfinBrowseView`: a genre's or decade's titles as a sortable grid (rating, name, year), opened from a tile.
- [x] 3.3 Strings: new Mac texts with German translations, "Home" → "Overview"; `LocalizationTests` green.

## 4. Verification

- [x] 4.1 Fernsy Dev on the demo server (`scripts/dev-run.sh`): the app opens on Start; window screenshots of Start at full and minimum window size; `IPTV_TESTRESUME=movie.<id>:600:5400` shows the large entry with "Resume"; `IPTV_TESTHOVER=1` screenshots 6 s apart differ in the backdrop.
- [ ] 4.2 Fernsy Dev with the local test Jellyfin (`scripts/jellyfin-test-server.sh`, `JF_TESTMANY=1`): Übersicht with suggestion, rows and tiles; a tile opens the grid; screenshots.
- [ ] 4.3 Same rows on both: Fernsy Dev and the Apple TV simulator on the demo server list Start's row titles in the same order (debug MCP or accessibility dump).
- [x] 4.4 `scripts/test.sh`, full Apple TV UI suite and the Mac build green.
- [ ] 4.5 The user checks Start and Übersicht in their Mac app (nightly) with their accounts, including hover.
