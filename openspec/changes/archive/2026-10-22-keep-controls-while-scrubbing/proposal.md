# Proposal

## Why

Dragging the scrub bar hides the controls after about 3 s although the mouse button is still
held: the hide timer restarts only when the drag begins, and while the slider tracks the mouse
neither hover nor mouse-move events reach the player, so nothing counts as activity. The bar
disappears under the cursor in the middle of seeking.

## What Changes

- While the user drags a slider in the controls (scrub bar for films, timeshift bar for live TV,
  volume), the controls stay visible and the cursor is not hidden.
- When the drag ends, the usual 3 s countdown starts again.

Out of scope:
- Changing the 3 s delay or other hide rules (paused, menus).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `playback`: "Transport controls and keyboard" – controls do not hide while a slider is being
  dragged.

## Impact

- `Fernsy/Views/PlayerScreen.swift` (`PlayerControls` reports drag start/end, `PlayerScreen`
  holds the controls during it), `README.md` not affected.
