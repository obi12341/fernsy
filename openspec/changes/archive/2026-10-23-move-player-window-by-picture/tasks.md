# Tasks

## 1. Implementation

- [x] 1.1 `VideoSurfaceView.mouseDown`: on a single click call `window?.performDrag(with:)` after the existing first-responder and activity handling; double-click unchanged; builds
- [x] 1.2 Verification by the user with a test DMG of this branch (decided instead of synthetic mouse events on the user's screen): drag from the picture's middle and near a corner moves the window, a plain click shows the controls without moving, a double-click toggles full screen, dragging the volume slider and the scrub bar does not move the window, controls still hide after 3 s – confirmed by the user ("klappt super")

## 2. Finish

- [x] 2.1 README note (dragging the picture moves the window); `openspec validate --all --strict`

## Workflow follow-up

- Archive after the user's review, then merge `change/move-player-window-by-picture` into `main` with the user's OK.
