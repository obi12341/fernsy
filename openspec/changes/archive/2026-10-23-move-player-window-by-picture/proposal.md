# Proposal

## Why

The player window can only be moved by its top edge (the hidden title bar). With a video
filling the window, users expect to grab the picture itself and drag the window, as in QuickTime
Player or IINA. Today the video view explicitly refuses window moves (`mouseDownCanMoveWindow`
is false since the first commit; no recorded decision behind it).

## What Changes

- Pressing on the picture and dragging moves the player window. A click without moving keeps
  doing what it does today (show the controls), a double-click still toggles full screen.
- The controls (top bar, bottom bar, menus, sliders) and the "next episode" card keep their own
  clicks and never move the window.
- In full screen nothing moves (macOS does not move full-screen windows).

Out of scope:
- Click on the picture to pause (not requested; would conflict with the drag start).
- Resizing by dragging the picture.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `playback`: new requirement "Moving the window by the picture".

## Impact

- `Fernsy/Player/VideoSurface.swift` (`mouseDown`: start a window drag for single clicks).
- No change to `PlayerScreen`'s overlays expected: subtitles, OSD, audio badge and the info
  overlay already let clicks through (`allowsHitTesting(false)`), the controls' empty middle
  (`Spacer`) is not hit-tested.
