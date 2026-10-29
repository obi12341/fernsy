# Design

## Context

`GuideView` (ios-app) nests a horizontal `ScrollView` in a vertical one. The channel column is a
`LazyVStack` beside it; the grid is a `LazyVStack` inside the horizontal scroll view. A stack
inside a horizontal scroll view is measured with unbounded height, so it builds all rows; each row
(`GuideRow`) runs `.task { loadGuide }` and, for archive channels, `loadPast`, and draws every
show between the axis start (start of the earliest archive day) and twelve hours ahead in a
`ZStack` of buttons placed by offset. `EPGStore` caches listings per channel and is not the
bottleneck; the view tree is.

The Apple TV guide shows a three-hour window and pages it by focus, so it never builds the whole
axis. Touch scrolling needs the continuous axis the spec asks for.

`FrameStats` (`IPTV_FRAMESTATS=1`, shared from FernsyTV) logs "frames: N late of M" once per second
while frames are late; the Apple TV scrolling tests already read it.

## Goals / Non-Goals

**Goals:**
- Build only what is on screen (plus a margin) in both directions.
- Load listings only for rows that appear; past days only when the visible span reaches them.
- Keep the look and behavior: fixed channel column, pinned hours, now line, opening half an hour
  before now, reach into the archive, tap rules.
- A repeatable measurement on the simulator against the demo server.

**Non-Goals:**
- The Apple TV and Mac guides.
- `EPGStore` request scheduling or caching.
- New guide features (jumping to a day, search).

## Decisions

1. **A horizontal scroll view around a vertical one with a lazy list of rows.**
   `ScrollView(.horizontal) { ScrollView(.vertical) { LazyVStack(pinnedViews: [.sectionHeaders]) } }`,
   the hour bar as the pinned section header. The vertical scroll view gets the viewport's height,
   so its lazy stack builds rows as they come on screen and their `.task`s start then.
   - Found while implementing: a single `ScrollView([.horizontal, .vertical])` was not lazy; its
     stack built every row like the old nesting. The order matters: the axis that holds the lazy
     stack must be the inner one.
   - The channel column (`PinnedColumn`): each row starts with its logo cell, shifted right by the
     horizontal scroll offset (`onScrollGeometryChange` on the visible rect) and drawn above the
     shows; the header corner does the same. The offset lives in a small `ObservableObject`
     (`GuideScroll`) held in `@State` and observed only by the pinned cells: as `@StateObject` on
     the guide it redrew the whole guide every frame.
   - Rows are `Equatable` (channel, listings range, window) and used with `.equatable()`, so a
     window or offset change does not rebuild rows whose input did not change.
   - Rejected: keeping the nested scroll views and making the outer list lazy only. The inner
     stack still lays out every row; that is the bug.
   - Rejected: paging a short window as on Apple TV. The spec asks for a grid that scrolls by
     touch both ways; paging by touch would be a different interaction.
   - Rejected for now: a `UICollectionView` with a custom layout. Most control and the usual
     answer for big grids, but a second UI technology in an otherwise SwiftUI app. Not needed:
     the user found the SwiftUI guide fluid on the iPad (task 3.3, 3.4).
2. **Rows draw only the visible span.** The visible time span comes from the horizontal offset
   and the viewport width, rounded out to whole hours with one viewport of margin on each side,
   and is passed to the rows. A row filters its shows (and gaps) to that span; the hour bar draws
   only the span's labels (drawing all of them cost most of the remaining late frames). The span
   moves in six-hour blocks, so rows re-filter only every few hours of scrolling, not every frame.
3. **Past days follow the visible span.** `loadPast` runs per row with the task id keyed on the
   visible span's start day, only when that span reaches more than three hours back (as today's
   condition, applied to what is visible rather than the axis start).
4. **Opening position unchanged.** The initial horizontal position stays "half an hour before
   now" via `ScrollPosition`; with one scroll view it is set as `scrollTo(point:)` keeping y at 0.
5. **Measurement.** A UI test on the iPad simulator (demo server, `IPTV_FRAMESTATS=1`) opens
   Programm, swipes down and up several times and back in time into the archive, then reads the
   app log: at most a few late frames per second of scrolling, and the guide requests no more
   rows than were on screen (logged as "guide row appears" in DEBUG). The same check is run once
   with the current code first, to have the before number.
   - `IPTV_TESTBIGLIVE=<n>` (DEBUG) repeats the channel list up to n channels (copies without
     listings), so the 24 demo channels reach provider scale.
   - Each XCTest drag stalls the app for 250-600 ms while XCTest snapshots its accessibility
     tree (about a quarter of the main thread in Time Profiler). The test therefore judges a
     freeze from 1 s, rows built (fewer than 150 of 400), and late frames per second; it cannot
     judge smoothness finer than that, which is why the user's check on the iPad decides.

## Risks / Trade-offs

- **Two-axis SwiftUI scroll views** have had quirks with pinned headers and direction locking;
  if the pinned hour bar or diagonal scrolling misbehave, the fallback is decision 1's rejected
  `UICollectionView`.
- **The demo server is small** (24 channels, 3 with 5 days of archive). It shows the fault (all
  rows, about 130 hours each) but not provider scale; the final check is on the user's iPad with
  the real channel list, which loads listings only (no stream, so the single-stream rule is not
  touched).
- **Offset-driven channel column** re-renders the logo cells while scrolling sideways; they are
  small (an image and a frame), and only the visible rows have one.
