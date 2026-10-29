# Tasks

## 1. Before

- [x] 1.1 Add a UI test on Start (demo server via `IPTV_SERVER` demo as in the other tests; `IPTV_TESTRESUME` to fill "Continue Watching", or `IPTV_TESTROWLIMIT` from design 3 if needed): a row with four or more cards above a row with three and a longer row below; focus the fourth card of the upper row, press Down, expect focus on the last card of the three-card row. Run it on the current code on the "Claude Apple TV" simulator and note that it fails (focus lands two rows down). Done as `RowByRowFocusUITests` with two Continue Watching cards: its cards are as wide as On Now's and the focused card past the fourth sits at the right edge, so three would still reach under it. Before: Down from `start.live.103` landed on `start.tonight.108`, two rows down.

## 2. Row by row

- [x] 2.1 Make `CardRow` a focus section (design 1, 2); the test from 1.1 passes.
- [x] 2.2 Up from a shorter row into a longer one lands in that row too: extend the test with Up from the three-card row's last card, expect focus in the row above.

## 3. Verify

- [x] 3.1 The full Apple TV UI test suite passes on "Claude Apple TV" (`DEVICE_NAME="Claude Apple TV" scripts/tv-uitest.sh`), in particular Start, Jellyfin overview, edge scrolling and tab tests. 49 passed, 9 skipped (Jellyfin server tests), 1 failed: `testPanelInEveryPlayer` lost the player element once; it passed on its own rerun (`StreamInfoUITests`).
- [x] 3.2 On the user's Apple TV WZ (Release build): the user confirms Down on Start and Jellyfin's Übersicht moves one row at a time. The user confirmed it on the Apple TV WZ (2026-10-29).
- [x] 3.3 `openspec validate --all --strict` passes.
