# Proposal

## Why

On Apple TV, a row with more cards than fit shows no part of the next card at the right screen
edge when it first appears, so nothing tells that the row goes on (user report 2026-10-29,
Jellyfin's Übersicht on the Apple TV: Zuletzt hinzugefügt ends after seven posters with empty
space; after scrolling a row right and back, the eighth poster shows at the edge).

Measured in the simulator (Übersicht, `JF_TESTMANY=80`): `CardRow`'s scroll view spans x 80 to
1840, the screen's safe area, not the screen. Its negative padding (tvos-edge-scrolling) only
reaches the safe-area edge. The eighth poster starts at x 1854, outside the scroll view, so the
lazy stack does not create it; `scrollClipDisabled` draws it only once scrolling has created it.

## What Changes

- Card rows on Apple TV span the whole screen width, so every card that is on screen exists
  from the start: half or part of the next card shows at the right edge while more follow.
- The first card stays where it is today, aligned with the page's titles.
- This covers the rows that stopped at the safe area: `CardRow` (Jellyfin's Übersicht, detail
  pages, Jellyfin search; Start's rows already reached the edge and stay as they are) and the
  recording rows in Aufnahmen. The player's channel strip already reaches the edge (the overlay
  ignores the safe area) and is left alone.

Out of scope: the Mac (its rows clip at the page margin and show a card partly when one falls
there); card sizes or the number of cards per screen; rows built without a lazy stack (the
category chips in Alle Kategorien), which already exist in full.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: "Scrolling content on Apple TV" gains a scenario: the next card shows at the right
  edge as soon as a row appears.

## Impact

- FernsyTV: `CardRow` and a new `EdgeToEdgeRow` in `Screens/LibraryComponents.swift`; the
  recording rows in `Screens/RecordingsScreen.swift`.
- UI test on Übersicht with the local test Jellyfin.
