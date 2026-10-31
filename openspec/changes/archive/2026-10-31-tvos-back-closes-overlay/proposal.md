# Proposal

## Why

On Apple TV, Back in the film, episode and recording player ends playback at once, even while
the timeline overlay is showing. The overlay appears on every click and swipe and at the start
of an item. A user who presses Back to hide it loses their place in the film, and the player
closes. The live player already handles Back in steps (overlay first, then stop). The players
for films, series and recordings should behave the same.

## What Changes

- In the Apple TV player for films, episodes, Jellyfin items, catch-up and cloud recordings,
  Back closes what is on top first:
  - the audio or subtitle panel (as today);
  - else the next-episode countdown, which is cancelled;
  - else the timeline overlay, which is hidden.
  Only Back with nothing on top stops playback.
- The recording player does the same with its timeline overlay.
- Hiding the overlay with Back does not restart its 6 s timer and does not show it again.

Out of scope:
- The live player: it already hides its overlays step by step before it stops.
- The failure card of the status layer: Back there still closes the player, as specified in
  "Playback failure on Apple TV".
- Mac, iPad and iPhone: they have no Back button in the player (the Mac leaves full screen with
  Esc, iOS has a close button).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: a new requirement for Back in the on-demand and recording players.

## Impact

- `FernsyTV/Screens/VODPlayerScreen.swift` and `FernsyTV/Screens/RecordingsScreen.swift`: the
  exit command handlers.
- Apple TV UI tests: the player tests that press Back to stop must first let the overlay hide,
  or press Back twice; a new test covers the order.
- iOS and Mac: unchanged.
