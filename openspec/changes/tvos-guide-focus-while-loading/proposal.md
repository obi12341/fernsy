# Proposal

## Why

Since rows of Apple TV's guide show a focusable bar while their programme loads
(tvos-guide-empty-channels), scrolling down fast can make the guide jump back up (user report
2026-10-28). Focus lands on a row's "Loading program …" bar; when the programme arrives, the
row replaces that bar with the shows, the focused view disappears, and tvOS moves focus to a
place of its own choosing, often rows above. Before, loading rows had nothing focusable and
were skipped, so this could not happen.

## What Changes

- When the programme arrives for the row with focus on its loading bar, focus moves to the cell
  of that row at the same time: the show running then (the window's time now, else its start),
  or a gap bar there. Focus never leaves the row because its content loaded.
- The same holds when a gap bar with focus is replaced by a show (the quick answer first, the
  full table later).
- Debug switch `IPTV_TESTEPGDELAY=<s>`: listings arrive that much later, to reproduce loading
  rows in tests.

Out of scope: the channel list view (its rows are always focusable buttons); the Mac guide (no
focus engine).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: "Program guide on Apple TV" gains a scenario: focus stays in its row while the row's
  programme loads.

## Impact

- FernsyTV: `GuideRow` in `Screens/GuideScreen.swift` (hand focus over when its cells change).
- FernsyCore: `EPGStore` debug delay.
- UI test with fast Down presses through loading rows.
