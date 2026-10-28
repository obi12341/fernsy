# Tasks

## 1. Backdrops

- [x] 1.1 FernsyCore: `MovieDetails.backdrops`, `SeriesInfo.backdrops` (full `backdrop_path` list), `JellyfinStore.backdropURLs(_:)`; unit tests with a list and a single value.

## 2. Living backdrop

- [x] 2.1 `LivingBackdrop` (design 1, 4): Ken Burns while active, cross-fade every 8 s, paused when inactive, Reduce Motion respected.
- [x] 2.2 Start: `StartBackdrop` uses it with the hero's backdrops; `Hero` reports its focus through `StartScroll`; entry text eases in (design 5).
- [x] 2.3 Jellyfin spotlight uses it (after `tvos-jellyfin-overview` is merged into this branch).

## 3. Verification

- [x] 3.1 UI test: focus on the large entry, screenshots 0 s and 6 s apart differ in the backdrop; focus moved into the rows, two screenshots are equal; screenshots for the user.
- [x] 3.2 StartScrollingUITests stays under its limit; IPTV_FRAMESTATS while the hero animates shows no late frames beyond the baseline.
- [x] 3.3 Full Apple TV UI suite and `scripts/test.sh` green.
- [ ] 3.4 Real Apple TV, Release build: the user judges the effect.
