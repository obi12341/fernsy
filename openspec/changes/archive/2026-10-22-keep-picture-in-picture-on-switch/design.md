# Design

## Context

- Every start from the main window (channel list, guide, films, series, recordings, Jellyfin,
  menu bar) sets `AppModel.nowPlaying`. `LibraryView` reacts with `openWindow(id: "player")`
  (`LibraryView.swift`, `.onChange(of: app.nowPlaying)`), which orders the single player window
  front – also when PiP has hidden it with `orderOut`. `PlayerScreen` reacts to the same change
  with `load(item)` → `engine.load…`, which keeps the same `displayLayer`, flushes it and starts a
  new session.
- While PiP runs, the display layer lives in `PictureInPictureStage`'s invisible window (see the
  archived `add-picture-in-picture` design: macOS mirrors the PiP source unscaled). The player
  window's video view has no layer meanwhile, so the window that pops up is empty.
- Observed by the user: after switching channels during PiP the PiP window keeps the old picture.
  Resolved: with the player window kept hidden (below) the PiP window shows the new channel; the
  "frozen" picture was the old channel's last frame while the new one loads (user's test with a
  DMG of this branch). Earlier analysis: Ruled out in a minimal app: a flush of the layer during PiP, and
  ordering the source window front during PiP – the mirror keeps updating in both cases. Not yet
  reproduced in Fernsy (`IPTV_TESTZAP` lands on the same channel; no switch for "start from the
  main window" exists).

## Goals / Non-Goals

**Goals:** a new item started from the main window plays in the running PiP window, with the
player window staying hidden; items without picture end PiP with "back".

**Non-Goals:** see proposal.

## Decisions

### Keep the player window hidden
`AppModel` gets a published `isPictureInPictureActive`, set by `PlayerScreen` when PiP starts
and cleared on "back" and close. `LibraryView` opens the player window for a new item only when
it is false.
- Rejected: let `openWindow` run and hide the window again in `PlayerScreen` – the window would
  flash up and become key.
- Rejected: end PiP on every switch (variant B in the discussion) – the user chose to keep
  watching in PiP while browsing.

### Find and fix the frozen PiP picture
First reproduce: debug switch `IPTV_TESTSWITCH=<s>:<live|movie>:<id>` calls the same `AppModel`
entry point the main window uses (`play(channel)` / `play(movie)`), so the test runs the real
path including the window handling. Then find the cause with the window handling fixed (it may
be the cause itself, since the reopened window takes focus while the layer is in the stage
window). Candidates to check in this order:
1. The reopened player window (already removed by the decision above).
2. The layer after `engine.load…` (synchronizer reset to time zero, `flush()` of the renderer)
   while it sits in the stage window – compare with the flush needed after "back".
3. The PiP controller's state for the new item (`invalidatePlaybackState()` on `media` change is
   already wired; check the time range switch live ↔ on-demand).
The fix stays in `PictureInPictureStage` / `PictureInPicture` where possible. Record the cause and
the fix here when found.
- Fallback if the picture cannot be kept live in place: end PiP with "back" on a switch (the
  spec's no-picture path), and record why.

### Loading picture in PiP
The PiP window mirrors only the video frames of the display layer: an extra sublayer on the layer
does not appear in PiP (tested in a minimal app), and sample-buffer PiP has no buffering state
for a system spinner. So while PiP runs, a switch starts `PictureInPictureLoadingCard`, which
renders frames (dark background, title, rotating spinner; 10 per second, marked "display
immediately") and enqueues them into the layer's video renderer.
- No two writers on the renderer: the card runs on its own serial queue; the playback session
  calls a hook right before it enqueues its first video frame, and the engine stops the card
  synchronously there. The card also stops on `engine.stop()`, on a failed or ended item, and
  when the new item has no video.
- The card's last frame stays until the item's first frame is due, so the switch shows: loading
  picture → first picture, without the old item's picture in between.
- Rejected: flush the old picture (black PiP) – black looks like an error.
- Rejected: an overlay layer or SwiftUI view – not mirrored into PiP.

### Frame size changes misplace the PiP mirror again
Tested in the minimal app: whenever the frames' pixel size changes while PiP runs (1920×1080 →
1280×720, → 3840×2160, and back), the mirror comes out shifted and cropped as before the
`add-picture-in-picture` workaround and stays so. Re-adding the layer or resizing the stage window
does not help; changing the layer's frame and setting it back does. `PictureInPictureStage.refit()`
does that 0.25 s and 0.9 s after a possible size change (the new size counts once a frame of it is
shown): when the loading picture starts, when the engine reports a new video size, and when the
new item plays. This also covers real channels with different resolutions, without the loading
picture.
- The loading picture uses the size of the current picture, so starting it changes nothing.
- `displayedPixelBuffer()` of the renderer returns nil while it plays, so the session hands every
  frame to `LastPicture` (lock-protected); the card draws on that frame (blurred, darkened).

### PiP only with a picture
Starting PiP before the first frame (reported as possible by the system) crashes inside AVKit
(`AVPictureInPictureSampleBufferDisplayLayerHostView` lays out an invalid size). PiP therefore
starts only when `LastPicture` holds a frame, and the button shows only while playing, paused or
buffering. Found with `IPTV_TESTSLOWSTART=<s>` (debug: delays every session start).

### Items without picture
When the new item reports no video track (`engine.media?.hasVideo == false`), `PlayerScreen`
calls `pip.restore()`: PiP ends as with "back" and the player window plays the item.

## Risks / Trade-offs

- [The refit relies on observed system behaviour] → harmless if it stops being needed; re-check
  with every major macOS release together with the other PiP workarounds.
- [Single-stream accounts: switching during PiP closes the old stream first] → unchanged engine
  behaviour; tests run on the demo server only.
