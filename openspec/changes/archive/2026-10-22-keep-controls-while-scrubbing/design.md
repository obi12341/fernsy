# Design

## Context

- `PlayerScreen.showControls(autoHide:)` shows the controls and starts a 3 s task that hides them
  (and the cursor) while playing. `PlayerControls` calls `onActivity` (= `showControls()`) on
  hover, button actions and at the start and end of a slider drag (`onEditingChanged`).
- During a drag the slider tracks the mouse; the scrub sliders' bindings only set `scrubValue`
  and report nothing, so the timer started at the drag's beginning hides the controls 3 s later.
  The volume slider reports activity on every value change but not while held still.

## Goals / Non-Goals

**Goals:** controls stay up for the whole drag; normal countdown after it.

**Non-Goals:** other hide rules.

## Decisions

### Hold the controls during a drag
`PlayerControls` gets `onDragging: (Bool) -> Void`. Each slider's `onEditingChanged` calls it
with `true` at the start and `false` at the end (scrub bar, timeshift bar, volume). `PlayerScreen`
counts active drags; while any is active, `showControls(autoHide: false)` cancels the hide task
(and nothing hides the cursor); when the last drag ends, `showControls()` starts the normal 3 s
countdown.
- Rejected: reporting activity on every value change of the scrub binding – holding the slider
  still for 3 s would still hide it.
- Rejected: a longer hide delay – does not fix holding, and slows hiding in normal use.

## Risks / Trade-offs

- [A drag end is never reported (e.g. window loses focus mid-drag)] → the count resets when the
  player item changes or the window closes, and any later activity restarts the countdown once
  the drag flag is cleared on the next `onEditingChanged(false)`.
