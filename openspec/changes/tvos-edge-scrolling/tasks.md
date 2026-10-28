# Tasks

## 1. Before

- [x] 1.1 UI test with the local test Jellyfin: scroll the Filme view down and an Overview row sideways, screenshots mid-scroll (the current overlap and popping, for comparison).

## 2. Layout

- [x] 2.1 JellyfinScreen: header inside the ScrollView as its own focusSection; ScrollView to the screen edges with content margins.
- [x] 2.2 CardRow: bleeds to the screen edges with the page margin as content margin (parameter, default 90); check Start, detail pages and Jellyfin's Overview align as before.

## 3. Verification

- [x] 3.1 The screenshot test again: no poster over the header, posters leave at the screen edge; screenshots for the user.
- [x] 3.2 Jellyfin, Start and detail UI tests and the full Apple TV UI suite green.
- [ ] 3.3 Real Apple TV, Release build: the user scrolls the Jellyfin tab and judges it.
