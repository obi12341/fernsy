# Proposal

## Why

Start shows the show on now for each channel in "Jetzt live" and tonight's shows, but it computes
them once when it appears. Left open for a while (the Mac in the background, an iPad on the
table), the cards keep the old show and progress until the user leaves Start and comes back.
The user saw it on the Mac; Apple TV and iPhone/iPad have the same code shape.

## What Changes

- "Jetzt live" cards on Mac, Apple TV and iPhone/iPad move on to the next show and update their
  progress every minute while Start is shown.
- Start keeps the guides of its live channels fresh while shown (reloads them when they run
  short), as the channel lists already do, instead of loading them once.
- "Heute Abend" is worked out again every minute: shows that ended drop out, and after 21:30
  the row turns into "Demnächst" as when Start opens.
- Apple TV and iPhone/iPad get the debug switch `IPTV_CLOCKOFFSET` the Mac already has, for the
  checks.

Out of scope:
- The other screens (guides, channel lists, player strip); they already follow the clock or are
  not reported.
- Refreshing the catalog rows (films, series, Jellyfin) while Start is shown.

## Capabilities

### New Capabilities

### Modified Capabilities
- `catalog`: Start on the Mac keeps its live rows current while shown.
- `apple-tv`: Start on Apple TV keeps its live rows current while shown.
- `ios-app`: Start on iPhone and iPad keeps its live rows current while shown.

## Impact

- `Fernsy/Views/StartView.swift`, `FernsyTV/Screens/StartScreen.swift`, `FernsyiOS/StartView.swift`:
  live cards in a minute timeline, guides through `EPGStore.keepFresh`, tonight's row recomputed
  per minute.
- A minute clock for Apple TV and iOS (`FernsyTV/Support`, shared with iOS), with
  `IPTV_CLOCKOFFSET` in debug builds, like the Mac's `LiveClock`.
- UI tests for Apple TV and iOS; no network change beyond the guide reloads the channel lists
  already make.
