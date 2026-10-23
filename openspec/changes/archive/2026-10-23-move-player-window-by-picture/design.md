# Design

## Context

- `VideoSurfaceView` (`Fernsy/Player/VideoSurface.swift`) is an `NSView` hosting the display
  layer under the SwiftUI overlays of `PlayerScreen`. It returns `mouseDownCanMoveWindow = false`
  and its `mouseDown` makes itself first responder, reports mouse activity (shows the controls)
  and toggles full screen on `clickCount == 2`.
- The player window uses `.windowStyle(.hiddenTitleBar)`: only the title bar strip moves it.
- Overlays above the picture: subtitles, bitmap subtitles, channel OSD, audio badge and the info
  overlay are `allowsHitTesting(false)`; `PlayerControls` is a `VStack` of top bar, `Spacer` and
  bottom bar (empty spacer area is not hit-tested); the Jellyfin "next episode" card is
  interactive by design.

## Goals / Non-Goals

**Goals:** drag the window from anywhere on the picture, keeping click and double-click
behaviour. **Non-Goals:** see proposal.

## Decisions

### `performDrag(with:)` from the surface's `mouseDown`
On a single click (`clickCount == 1`) the surface keeps its current work (first responder,
activity) and then calls `window?.performDrag(with: event)`. AppKit runs the drag loop and moves
the window only if the pointer actually moves; a plain click returns at mouse-up without moving.
The second click of a double-click arrives with `clickCount == 2` and toggles full screen as
today, without a drag. In full screen AppKit does not move the window.
- Rejected: `isMovableByWindowBackground` with `mouseDownCanMoveWindow = true` – AppKit then
  handles the press itself and the surface's `mouseDown` (controls, double-click) no longer runs
  reliably.
- Rejected: a SwiftUI `WindowDragGesture` on an overlay – would need a hit-testable layer over
  the picture, which then also takes the clicks and double-clicks from the surface.

## Risks / Trade-offs

- [A press that starts a drag also counts as activity and shows the controls] → intended; the
  controls hide again after 3 s.
- [An overlay that is hit-testable by accident blocks dragging there] → checked overlay by
  overlay (Context); verified by dragging at several points (tasks).
