# Tasks

## 1. Measuring

- [x] 1.1 Debug switches `IPTV_TESTBIGCATALOG=<n>` (films and series repeated up to n, in memory) and `IPTV_FRAMESTATS=1` (late frames per second in the log); DEVELOPMENT.md.
- [x] 1.2 UI test: demo server with `IPTV_TESTBIGCATALOG=30000`, scroll Start down to the last row and back, read late frames from the log; record the numbers before the changes in design.md.

## 2. Start

- [x] 2.1 `StartScroll` and `StartBackdrop`: the offset is read only by the backdrop, opacity rounded to 2 % steps.
- [x] 2.2 `StartRows` holds every row; StartScreen rebuilds each part keyed on its inputs (catalog, resume revision, recorder, guide revision, Jellyfin home); `body` computes nothing from the catalog.
- [x] 2.3 TVModel keeps `moviesByID` and the newest films and series when the catalog is applied; `continueWatching` and `recentlyAdded` use them.
- [x] 2.4 `LazyVStack` for Start's rows.

## 3. Verification

- [x] 3.1 The scroll test again: late frames after the changes, both numbers in design.md.
- [x] 3.2 StartUITests, LibraryUITests and the full Apple TV UI suite green; `scripts/test.sh` green.
- [ ] 3.3 Real Apple TV, Release build, the user's provider: the user scrolls Start and judges the feel.
