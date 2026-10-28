# Tasks

## 1. Data

- [x] 1.1 Check that the grid request delivers runtimes; if not, add `RunTimeTicks` to `gridFields` (FernsyCore) and refresh the cache once.
- [x] 1.2 FernsyCore `JellyfinOverview.build(films:series:now:)`: spotlight candidates, the rows of design 2, genre and decade tiles, the numbers; thresholds as constants.
- [x] 1.3 FernsyCore unit tests of the rules with a hand-made library (each row's filter and order, empty rows left out, spotlight without repeats).

## 2. Screen

- [x] 2.1 Übersicht as a `LazyVStack` in the order of design 5; overview kept in `@State`, rebuilt on library changes.
- [x] 2.2 Spotlight with backdrop, "Abspielen", "Anderer Vorschlag", "Details".
- [x] 2.3 Rows with posters (badge "n Folgen übrig" for Serien fast durch), Stöbern tiles and the numbers line.
- [x] 2.4 `JellyfinBrowse` grid for a genre or decade with the sort options; Back to Übersicht.
- [x] 2.5 German strings.

## 3. Verification

- [x] 3.1 UI tests with the local test Jellyfin and `JF_TESTMANY`: spotlight and "Anderer Vorschlag", a genre tile opens its grid, rows present; screenshots for the user.
- [x] 3.2 Full Apple TV UI suite green.
- [ ] 3.3 Real Apple TV, Release build, the user's Jellyfin: the user judges the page.
