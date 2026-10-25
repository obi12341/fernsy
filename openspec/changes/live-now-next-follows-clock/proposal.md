# Proposal

## Why

The Live TV list stays at the moment it was drawn. The user's screenshot was taken at 22:32.
The rows still showed the show that ended at 22:30, with "Next 22:30 …", and the progress
bar had stopped. Only the detail pane was current, because selecting a channel had just
redrawn it.

The rows, and the detail pane while it stays open, compute "now" only when SwiftUI redraws
them. They redraw when the channel's programme changes, but not when time passes.

## What Changes

- The channel rows (Live TV, Favourites, Recently Watched, search, and the channel rows in
  the series view) follow the clock. Current show, progress and next show move on at the
  latest one minute after a show change.
- The detail pane follows the clock in the same way: the current show with its remaining
  time and progress, the list of following shows, and their "Record"/"Scheduled" buttons.
- A channel's programme is fetched again while its row stays visible, as soon as it is no
  longer fresh (the existing rule: it runs out within 20 hours or is half a day old). Before,
  this only happened when the row appeared. The rule itself is unchanged.

Out of scope:
- the provider-unreachable notice;
- the guide grid, which already redraws every 30 s;
- the player's caption and timeline;
- the frequency of the catalog refresh.

## Capabilities

### New Capabilities
- (none)

### Modified Capabilities
- `live-tv`: "Channel list with now and next" — rows and pane follow the clock.

## Impact

- `Fernsy/Views/ChannelListView.swift`:
  - `NowNextLine` is drawn from a minute clock;
  - `ChannelRow`'s programme task checks freshness again while the row is visible.
- `Fernsy/Views/ChannelDetailPane.swift`: the pane's body is drawn from the same clock.
- `Fernsy/Xtream/EPGStore.swift`: a `needsRefresh(_:)` query for the existing freshness rule.
- No new strings. README: a debug switch for the test, if one is needed.
