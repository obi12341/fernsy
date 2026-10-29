# Tasks

## 1. Rows to the screen edge

- [x] 1.1 `EdgeToEdgeRow`: measure how far the row reached into the safe area from the given and reached widths (design 2).
- [x] 1.2 `CardRow` on `EdgeToEdgeRow`: ignore the horizontal safe area, content margin `margin + side` (design 1).
- [x] 1.3 Recording rows (`RecordingsScreen`) on `EdgeToEdgeRow`; the player's channel strip unchanged (design 3).

## 2. Verification

- [x] 2.1 UI test on Übersicht with the local test Jellyfin (`scripts/jellyfin-test-server.sh`, `JF_TESTMANY=80`): without moving right, a poster of Zuletzt hinzugefügt reaches past the right screen edge, and the first poster starts at the row title's x; screenshot.
- [x] 2.2 Screenshots of Start (demo server), Aufnahmen (`IPTV_FRESHRECORDINGS`/test recordings) and the player's channel strip: first cards under their titles, the next card at the right edge; moving right through a row (`JellyfinEdgesUITests`) keeps the margin and lets cards leave at the left edge.
- [x] 2.3 `JellyfinOverviewUITests`, `StartUITests`, `StartScrollingUITests`, `RecordingsUITests`, `PlayerUITests` and the full Apple TV UI suite green.
- [ ] 2.4 Real Apple TV, Release build: the user opens Übersicht and sees part of the next poster at the right edge of Zuletzt hinzugefügt.
