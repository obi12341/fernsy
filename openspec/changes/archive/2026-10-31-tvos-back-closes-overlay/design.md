# Design

## Context

See proposal.md for the motivation. Today:
- `VODPlayerScreen.onExitCommand` closes the track panel if one is open, else calls
  `model.stop()`.
- `RecordingPlayerScreen.onExitCommand` (in `RecordingsScreen.swift`) always calls
  `model.stop()`.
- Both show their overlay (`showsOverlay`) at the start, on a click and on every move or
  Play/Pause (`touch()`), and hide it 6 s after the last input (`task(id: lastInput)`).
- The live player's `PlayerScreen.back()` already steps down its modes: tabs, tracks or strip →
  info → hidden → stop.

## Goals / Non-Goals

**Goals:**
- One Back press closes exactly one layer, in the order the user sees them (topmost first).

**Non-Goals:**
- Changing what shows the overlay or how long it stays.

## Decisions

### 1. Order: track panel, countdown, overlay, stop

The track panel and the countdown card sit above the overlay and hold the focus, so they close
first. The countdown counts as a layer. Back while it runs cancels it, as its "Cancel" button
does, which also stops Jellyfin's autoplay. Otherwise a Back meant to dismiss the card would
end the series session.

Rejected: Back during the countdown starts the next episode at once. Back never means
"continue" anywhere else in the app.

### 2. Hiding with Back does not call `touch()`

`touch()` shows the overlay and restarts its timer. Back only sets `showsOverlay = false`, so
the overlay does not flash back. The live player calls `touch()` in `back()` for its own modes.
The on-demand players do not copy that.

### 3. The status layer keeps its own Back

While the failure card is up, the player is not focusable (`failed`) and the card handles
Back (close). Nothing changes there.

## Risks / Trade-offs

- [UI tests that press Back once to stop a film or recording] → They wait for the overlay to
  hide or press Back twice. The MCP `stop_playback` path is unaffected.
- [Users used to one press] → Two presses only when the overlay is up. That matches the live
  player and tvOS's own player.
