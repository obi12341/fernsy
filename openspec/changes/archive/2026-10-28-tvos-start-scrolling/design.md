# Design

## Context

- `StartScreen.body` computes `model.continueWatching`, `model.recentlyAdded`,
  `model.startChannels`, `model.tonight(on:)`, `nextUpEntries` and `recordingEntries` on every
  evaluation; only the catalog rows (`StartRows`, tvos-start-rows design A) are cached in `@State`.
- `onScrollGeometryChange { $0.contentOffset.y } action: { scrolled = $1 }` stores the offset in
  StartScreen's own `@State`; every scroll frame invalidates the whole `body`.
- `recentlyAdded` sorts all films per call; `continueWatching` does `movies.first(where:)` per
  started key; `tonight` scans each live channel's guide entries.
- The outer stack is a plain `VStack`; every row (and its `LazyHStack`) is created at once.
  Images are already downsampled off the main thread (`ImagePipeline`, `ShouldCacheImmediately`).
- TVModel publishes 30+ properties; recorder, Jellyfin and guide changes also fire its
  `objectWillChange`, so Start's `body` runs on many unrelated changes too.

## Goals / Non-Goals

**Goals:**
- No work proportional to the catalog while scrolling; `body` cheap enough to run on any model change.
- Measured: dropped frames while scrolling Start with a large catalog, before and after.

**Non-Goals:**
- Changing what Start shows or its order; other screens; splitting TVModel into smaller
  observables (a larger refactor, only if measuring shows it is still needed).

## Decisions

1. **The scroll offset lives in the backdrop alone.** A small `@Observable` `StartScroll` holds
   the offset; `onScrollGeometryChange` writes it, and only `StartBackdrop` (the background
   view, given the object) reads it, so SwiftUI re-renders just the backdrop per frame. The
   opacity is also rounded to 2 % steps (12 points of offset), so most frames change nothing at all. Rejected:
   `.visualEffect` on the backdrop (it cannot see the scroll view's offset, the backdrop sits
   behind it); dropping the fade (a visible design element).

2. **All rows in one cached value, rebuilt per input.** `StartRows` grows to hold every row:
   resume, next up, live channels with source, tonight, recently added, categories, recordings,
   best rated. `StartScreen` keeps it in `@State` and rebuilds the parts in `.task(id:)` /
   `onChange` keyed on what each part reads: catalog counts (as today), a resume revision
   (ResumeStore change count), recorder list, guide revision of the live channels, Jellyfin
   home. Rejected: memoising inside TVModel's computed properties (invalidation spread across
   the model, harder to follow).

3. **Indexes with the catalog.** When the film/series lists are applied, TVModel keeps
   `moviesByID` and the 12 newest films and series (one sort per catalog load, not per call).
   `continueWatching` and `recentlyAdded` use them.

4. **`LazyVStack` for Start's rows.** Rows below the screen are created as they approach.
   Focus moving down into a row not yet built works with lazy stacks on tvOS (the next row is
   inside the prefetch range); the UI tests that walk all rows (StartUITests) confirm it.
   Rejected: `List` (its focus and row styling fight the design's cards).

5. **Measure with debug switches.** `IPTV_TESTBIGCATALOG=<n>` repeats the demo account's films
   and series with new ids up to n items (in memory, after the catalog loads), so the simulator
   has a large catalog without a real provider. `IPTV_FRAMESTATS=1` runs a `CADisplayLink` and
   logs, once per second while frames are late, how many frames took over 1.5× the frame time
   ("frames: 7 late of 60"). A UI test scrolls Start down and up with 30,000 films and reads the
   log (MCP `get_log`); numbers before and after go into this design.

## Measurements

Simulator (Apple TV 4K 3rd gen, tvOS 27), demo server with `IPTV_TESTBIGCATALOG=30000`,
`StartScrollingUITests`: 14× down, 14× up, 0.5 s apart.

| State | Late frames in 21 s | Frame rate while moving |
|---|---|---|
| Before (two runs) | 139, 136 | about 10 per second (each frame ~100 ms) |
| After (decisions 1–4) | 14 | about 59 per second |

The test now fails above 40 late frames, about three times the value after the changes, so a
regression shows without flaky failures from simulator noise.

## Risks / Trade-offs

- [A stale row if an input is missed in the keys] → each row's key names exactly what the row
  reads; the UI tests for Continue Watching and Tonight cover the two that change while Start
  is open.
- [The simulator is faster than an Apple TV] → the frame counter also runs on the real device
  with a Release-like build; the user checks the feel there.
