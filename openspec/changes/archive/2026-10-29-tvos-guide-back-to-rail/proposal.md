# Proposal

## Why

Since catch-up, Left at the start of Apple TV's guide window pages back into the archive while
any shown channel has one (up to 7 days). Left therefore no longer reaches the rail on the left,
so the category column cannot be opened from the guide without pressing Left up to a week's
worth of hours. `LiveAndGuideUITests` (`testTheRailOpensTheColumn`, `testSourceAndViewAreKept`)
fail in CI on main since acf53db for this reason (the demo server's channels 101–103 have
archives).

## What Changes

- Back in the guide grid returns a window paged back or ahead to the current one (now), focus
  staying in its row.
- Back in the guide grid on the current window moves focus to the rail; Back on the rail goes to
  the tab bar as before.
- Left keeps paging into the archive as catch-up specified; without archive channels it still
  reaches the rail at today's window start.

Out of scope: the channel list view (its category column is always reached with Left); the Mac
guide (day stepper, no focus engine); a day chooser above the grid (rejected, see design).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `catch-up`: "Apple TV's guide reaches into the archive" gains how to get back: Back returns to
  now, then to the rail.

## Impact

- FernsyTV: `GuideScreen` (Back on the grid).
- UI tests: `LiveAndGuideUITests` reach the rail with Back; a new test for Back from a paged-back
  window.
