# Tasks

## 1. Hold the controls while dragging

- [x] 1.1 `PlayerControls.onDragging` from the scrub bar, the timeshift bar and the volume slider; `PlayerScreen` keeps the controls (and cursor) visible while a drag is active and restarts the 3 s countdown when it ends
- [x] 1.2 Verify on the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, `IPTV_AUTOPLAY=movie:500`, then `live:101`) with a scripted mouse drag (press on the scrub bar, move, hold 8 s, release): screenshots during the hold show the controls, and 4 s after release they are hidden; same for the timeshift bar

## 2. Finish

- [x] 2.1 Regression: without a drag the controls still hide after 3 s (demo film); `openspec validate --all --strict`

## Workflow follow-up

- Archive after the user's review, then merge `change/keep-controls-while-scrubbing` into `main` with the user's OK.
