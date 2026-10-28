# Proposal

## Why

In Live TV's guide on Apple TV only shows are focusable. A channel whose provider sends no
listings shows the text "No program information" and nothing else, so focus skips its row and
the channel cannot be played from the guide at all (user report 2026-10-28). The same holds while
a row's programme is still loading, and for the stretch of a row where the listings have a gap
or end early. The Mac solved this already ("Channels without program data": a hatched bar that
plays the channel).

## What Changes

- A row without listings in the visible window shows a focusable bar across the window that
  reads only "No program data" (user decision 2026-10-28: no hint line, unlike the Mac);
  clicking it plays the channel full screen.
- While a row's programme loads, the same bar reads "Loading program …" and also plays the
  channel when clicked, so focus can land on every row from the start.
- Gaps of 15 minutes or more between shows (and before the first or after the last show in the
  window) become focusable bars of the gap's width; clicking one plays the channel.
- Moving focus up and down through the guide stops on every channel, including those without
  listings; Left/Right paging at the window's edges works from these bars as from shows.

Out of scope: the Mac guide (unchanged); the channel list view (its rows are always focusable);
recording without listings (nothing to schedule).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: "Program guide on Apple TV" gains rows without listings, while loading and gaps
  that can be focused and play the channel.

## Impact

- FernsyTV: `GuideRow` in `Screens/GuideScreen.swift` (the bar, gaps, paging); German strings.
- Debug switch `IPTV_TESTNOEPG=<channel id>` (exists on the Mac) also on Apple TV for the test.
- UI test on the demo server.
