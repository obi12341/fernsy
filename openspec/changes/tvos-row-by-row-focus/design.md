# Design

## Context

Every horizontal row on Apple TV is a `CardRow` (`LibraryComponents.swift`): an `EdgeToEdgeRow`
(horizontal `ScrollView` reaching to the screen edges) around a `LazyHStack`. Rows sit in a
`LazyVStack` on Start, Jellyfin's Übersicht, the series page and search; none of them is a focus
section, so Down is resolved by the focus engine's geometry over the whole page: the nearest
focusable item below the focused card's frame. Under the fourth card of a four-card row there is
nothing in a three-card row, so the engine picks the card below it two rows down.

The hero on Start and the grids already use `.focusSection()` for the same reason (headers,
sort switches).

## Goals / Non-Goals

**Goals:**
- Up and Down from any card row land in the adjacent row, on the card nearest the focused one.
- One fix in the shared row, so every screen with rows gets it.

**Non-Goals:**
- Remembering a row's last focused card when coming back to it (tvOS does this for focus
  sections by default; it is not specified here and not tested).
- Grids, the guide, the channel list, the player's strip.

## Decisions

1. **Each `CardRow` is a focus section.** `.focusSection()` on `CardRow` makes the row one target
   for the engine: Down from a row searches for the next section below, then focuses the item in
   it nearest to the origin, which is the last card when the row is shorter.
   - Rejected: `onMoveCommand` handling Up/Down and setting `@FocusState` by row index. It
     needs each screen to know its rows and their cards, duplicates what the engine does, and
     fights the engine's own move animation.
   - Rejected: padding short rows with invisible focusable spacers. Focus could land on nothing
     visible.
2. **Where the section goes.** On the `EdgeToEdgeRow`'s scroll view inside `CardRow`, which spans
   the full screen width (it reaches past the page margin), so a card at any horizontal position
   finds the row. If focus sections on scroll views reaching into the safe area misbehave, the
   section moves to the row's container (title and row) on each screen instead.
3. **Test on Start against the demo server.** Start's rows are shaped by data the UI tests can
   set: "Continue Watching" from `IPTV_TESTRESUME`, "On Now" from the demo's channels. The test
   builds a row with at least four cards above one with three and a longer row below, focuses
   the fourth card, presses Down, and checks the focused card's identifier is the shorter row's
   last card. If the demo's rows cannot be shaped that way, a DEBUG switch limits a Start row to
   n cards (`IPTV_TESTROWLIMIT=<row id>:<n>`).

## Risks / Trade-offs

- [Focus sections change Up into the tab bar or into the hero] → The existing Start, Jellyfin
  and tab UI tests (Up from the first row reaches the tab bar, hero focus) run with the change.
- [Left/Right at a row's end] → A section does not trap horizontal moves; the row's own scroll
  behavior stays. Covered by the existing edge-scrolling tests (JellyfinEdgesUITests,
  StartScrollingUITests).
