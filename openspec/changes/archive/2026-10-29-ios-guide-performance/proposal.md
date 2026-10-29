# Proposal

## Why

On the iPad the program guide (Programm) is unusable: scrolling lags and the whole app seems to
freeze. `FernsyiOS/GuideView.swift` builds far more than is on screen:

- The rows sit in a `LazyVStack` inside a horizontal `ScrollView` inside the vertical one. The
  horizontal scroll view gets unbounded height, so that stack is not lazy vertically: every
  channel of the source gets a row at once, and every row starts its listings request
  (`loadGuide`) and, on archive channels, the past days (`loadPast`).
- The axis reaches back to the earliest archive day (`Archive.reach`), so with a week of archive
  it is over 8 days wide (about 43,000 pt at 220 pt per hour). Each row draws every show of that
  span as a button with its own background, about 150 to 200 per channel.

With a provider's channel list (hundreds of channels) that is tens of thousands of views and
hundreds of requests on opening, and SwiftUI lays them out again while scrolling. The demo server
(24 channels, 3 with 5 days of archive) already builds about 3,000 cells.

## What Changes

- The guide becomes one scroll view that scrolls both ways, with a lazy list of rows: only the
  rows on screen (plus a margin) exist, and only they load listings.
- Each row draws only the shows in the visible time span plus a margin, not the whole axis.
- The channel column stays at the left edge and the hours at the top, as now; the axis keeps its
  full reach into the archive, and the guide still opens half an hour before now.
- A UI test on the iPad simulator scrolls the guide with frame statistics on and fails on
  stalls.

Out of scope: the Apple TV and Mac guides (they page a short window already), what the guide
shows or what tapping does, the listings cache and the provider requests themselves.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ios-app`: "Program guide on iPhone and iPad" also requires that scrolling stays fluid with a
  provider-sized channel list and archive, loading listings only for the channels shown.

## Impact

- `FernsyiOS/GuideView.swift` (layout rewritten; `GuideRow`, `GuideCell`, `Placement` adapted).
- `FernsyiOSUITests/FernsyiOSUITests.swift` (a guide scrolling test with `IPTV_FRAMESTATS=1`).
- No change to `FernsyCore`'s `EPGStore` or to the shared model.
