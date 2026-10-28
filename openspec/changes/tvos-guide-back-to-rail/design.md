# Design

## Context

- `GuideScreen` (FernsyTV/Screens/GuideScreen.swift) puts the rail (`rail.source`, a button with
  `@FocusState railFocused`) left of the grid. `GuideRow.page` turns Left at the window's start
  into paging back while `windowStart > earliest`; catch-up set `earliest` to the start of the
  day `Archive.reach(of: channels)` days back. With any archive channel shown, Left at the window
  start never reaches the rail until that day.
- The rail is disabled while the window is paged ahead (so Left pages back there).
- Back on a screen's top level goes to the tab bar (apple-tv "Navigation on Apple TV"); the
  guide has no Back handler of its own.

## Goals / Non-Goals

**Goals:**
- The rail is reachable from the guide in any window with one or two presses.
- Paging into the archive stays on Left, as catch-up specified.

**Non-Goals:**
- Changing the channel list view or the Mac guide.

## Decisions

1. **Back on the grid.** `.onExitCommand` on the grid's scroll view (not on the rail, so Back on
   the rail keeps going to the tab bar): when `windowStart != defaultStart()` it sets
   `windowStart = defaultStart()`; otherwise it sets `railFocused = true`. tvOS convention: Back
   leads out to the sidebar, then to the tab bar. Rejected: a day chooser above the grid with Left
   back to its old meaning (one more control, and Up from the first row reaches the tab bar
   today); Left only back to this morning (yesterday, where most catch-up happens, again behind
   a chooser).

2. **Focus after returning to now.** The focused cell's id vanishes when the window moves; the
   row hands focus to the cell covering now (tvos-guide-focus-while-loading, `keepFocus`), so
   focus stays in its row. This change builds on that branch.

3. **Tests.** `LiveAndGuideUITests` reach the rail with Down then Back instead of Left twice; a
   new test pages back past this morning, presses Back (day title "Today", focus in row 101),
   presses Back again (rail focused).

## Risks / Trade-offs

- [Users used to Back leaving the guide for the tab bar] → one more press; the rail sits where
  focus would go next anyway, and Up still reaches the tab bar directly.
- [Back pressed while a confirmation dialog is open] → the dialog handles Back itself; the grid
  is not focused then.
