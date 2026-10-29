# Design

## Context

- `CardRow` (FernsyTV/Screens/LibraryComponents.swift, tvos-edge-scrolling design 3) is a
  horizontal `ScrollView` with a `LazyHStack` (spacing 40), `.contentMargins(.horizontal, 90)`,
  `.scrollClipDisabled()` and `.padding(.horizontal, -90)` so it bleeds past the page margin.
- Measured (simulator, Übersicht, `JF_TESTMANY=80`, frames from XCUITest): the page's content
  starts at x 170 (safe area 80 + page margin 90); the row's scroll view spans x 80–1840; the
  posters (200 wide) sit at 174, 414, … 1614. The eighth would sit at 1854: outside the scroll
  view, so `LazyHStack` never creates it until scrolling does. Afterwards it stays created and
  `scrollClipDisabled` draws it up to the screen's edge, which is why scrolling right and back
  "fixes" the row.
- Tried in the simulator: the margin as padding inside the content instead of `contentMargins`
  changes nothing (the scroll view stays 80–1840). Adding
  `.ignoresSafeArea(.container, edges: .horizontal)` after the negative padding makes the scroll
  view span 0–1920 and creates the eighth poster at once, but the content loses the safe-area
  inset (first poster at 94 instead of 174). Measuring the row's global `minX` to make up for it
  is unreliable: during the tab transition it reports 170, 90 and 57.
- The same pattern (lazy stack, bounded by the page, `scrollClipDisabled`) is in the recording
  rows (`RecordingsScreen`, `LazyHStack` in a page padded by the safe area).

## Goals / Non-Goals

**Goals:**
- Every card on screen exists as soon as its row appears, up to both screen edges.
- Card positions stay as they are (first card aligned with the page's titles).

**Non-Goals:**
- Changing card sizes, spacing or the Mac.

## Decisions

1. **Rows reach into the horizontal safe area.** `EdgeToEdgeRow` (used by `CardRow` and the
   recording rows) adds `.ignoresSafeArea(.container, edges: .horizontal)` after the negative
   page margin, so its scroll view spans the screen where the page stops at the safe area. Its
   content margin becomes `margin + side`, where `side` is how far the scroll view actually
   reached out, so the first card stays where it was. Rejected: a non-lazy `HStack` (creates
   every card of up to 48 per row and their images at once; Start's scrolling frame limit would
   suffer).

2. **`side` from sizes, per row.** The row measures the width its page gives it (a zero-height
   `Color.clear` beside the scroll view in a `ZStack`) and its scroll view's width after reaching
   out; `side = (reached - given - 2·margin) / 2`. Sizes hold still during transitions. On pages
   whose content already reaches the screen's edge (Start) nothing is ignored and `side` is 0.
   Tried and rejected on the way:
   - the row's own `safeAreaInsets.leading` read before `ignoresSafeArea`: SwiftUI reports 0
     inside the page, so the first card moved to x 94;
   - the row's global `minX`: 170, 90 and 57 during the tab transition;
   - one inset measured at the root (`RootScreen`, 80) for every row: on Start, in Aufnahmen and
     in the player the rows did not reach out the same way, and their first cards moved 80
     points right of the titles.

3. **The player's channel strip stays as it is.** Its overlay ignores the safe area, so the
   strip already reaches the screen's edge and shows the next card (screenshot before the
   change); applying the row there moved its first card off the pills.

4. **Test.** A UI test on Übersicht (local test Jellyfin, `JF_TESTMANY=80`) checks, without
   moving right, that a poster of Zuletzt hinzugefügt exists whose frame starts before the
   screen's right edge and ends past it, and that the first poster still starts where the row's
   title starts.

## Risks / Trade-offs

- [Focus scrolling: tvOS keeps the focused card inside the scroll view's bounds, which now reach
  the screen edge] → `contentMargins` still keep the margin, as the focus engine scrolls to the
  content margins; checked by moving right through a row (the existing edge test screenshots).
- [A row that reaches out on one side only] → `side` assumes both sides; every row using it
  sits in a page with the margin on both sides.
