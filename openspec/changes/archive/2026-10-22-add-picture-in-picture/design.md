# Design

## Context

- `PlayerEngine.displayLayer` (`AVSampleBufferDisplayLayer`) is attached to the
  `AVSampleBufferRenderSynchronizer` and shown by `VideoSurfaceView` in the single player window
  (`Window("Wiedergabe", id: "player")`). All sources render through it.
- Subtitles, controls, OSD and the info overlay are SwiftUI views above that layer.
- Closing the player window runs `PlayerScreen.onDisappear` → `engine.stop()`, which releases
  the stream (single-stream accounts). `MenuBarSupport.windowWillClose` switches to the
  accessory policy when the last titled window closes; hiding a window (`orderOut`) does not.

## Goals / Non-Goals

**Goals:** native PiP for every source with the player window hidden meanwhile; back and close
behave as described in the spec.

**Non-Goals:** see proposal.

## Decisions

### Sample-buffer PiP on the existing layer
`PictureInPicture` (new, owned by the engine) creates
`AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer: displayLayer,
playbackDelegate: self))`. The delegate maps:
- `setPlaying` → `engine.setPaused(!playing)`;
- `timeRangeForPlayback` → on-demand: the item on the layer's clock (`clockTime − position`,
  duration); live/timeshift: `CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)`
  (PiP shows live and then offers no skip buttons; the skip interval is the system's, 10 s);
- `isPlaybackPaused` → `engine.isPaused`;
- `skipByInterval` → `engine.seek(by:)` (timeshift seek for live);
- `didTransitionToRenderSize` → nothing (the layer scales itself).
`invalidatePlaybackState()` is called when pause, duration or live state change.
- Rejected: AVPlayer-based PiP – Fernsy does not use AVPlayer.
- Rejected: an own always-on-top mini window – PiP is the system's, works across Spaces and full
  screen apps, and costs less.

### Working around the unscaled PiP mirror (macOS 26.4 / 27.0, FB22411168)
On macOS the PiP window does not take the display layer over but mirrors it through a
`CALayerHost` at 1:1 – without scaling. Result: the PiP window shows only the bottom-left part of
the picture at double size (reproduced in a minimal app without Fernsy code; AVPlayerLayer PiP is
fine; reported in the Apple developer forums, thread 821582, no answer from Apple). Inside the PiP
window a second, empty black view (`AVPictureInPictureCALayerHostView`) keeps the original layer
size and covers the top of the picture (about 21 pt at the default PiP size).
- Fix: `PictureInPictureStage`. On `willStart` the display layer moves out of the player view into
  an invisible borderless window of its own (alpha 0, no mouse events, not in the Windows menu or
  window cycling); on `didStart` the PiP window – the window that appeared since `willStart`,
  found without private class names – is observed and the stage window and layer always get its
  content size. The mirror then is exactly as large as the PiP window. The stale overlay is hidden
  by its class name (a string comparison, no private API); if a later macOS renames or drops it,
  nothing is hidden and only the top strip stays covered. If Apple starts scaling the mirror, the
  layer already has the PiP size, so the result stays right.
- On "back"/close the layer returns to the player view and is flushed: without the flush it stayed
  black after moving back between windows; the session refills it at once (no visible gap).
- Rejected: resizing the (invisible) SwiftUI player window to the PiP size, as suggested in the
  forum – works during PiP, but on the way back SwiftUI's `NSHostingView.updateAnimatedWindowSize`
  set the window to 0×0.
- Rejected: resizing only the layer inside the player window – the mirror then showed it shifted.
- Rejected: transforms (`sublayerTransform`, scale) on the layer, `contentsScale` 1 on the layer
  and its internal sublayers, other video gravities, `sampleBufferRenderer` – no effect on the
  mirror. A layer outside any window cannot start PiP.
- Rejected (for now): an own floating window instead of system PiP – more work; the stage keeps
  the system's PiP with its controls, Spaces and full-screen behaviour.

### Window while PiP runs
- Start (button or P): `startPictureInPicture()`; on `didStart` the player window is hidden with
  `orderOut` (not closed, so the engine and stream keep running and the menu bar policy is
  untouched).
- "Back" (`restoreUserInterfaceForPictureInPictureStop`): show the window (`makeKeyAndOrderFront`),
  complete with `true`; the layer returns to the view.
- Close (`didStop` without a restore): stop playback the same way as closing the player window
  (`engine.stop()`, release the item, then close the hidden window), so recordings on the
  channel keep their connection as today.
- The PiP button is hidden when `isPictureInPicturePossible` is false (e.g. no video yet, radio).

### Test hook
Debug `IPTV_TESTPIP=<s>` starts PiP after `<s>` seconds; `IPTV_TESTPIP=<s>:back:<t>` returns to
the player after `<t>` seconds. Closing cannot be driven from code: `stopPictureInPicture()`
always goes through "restore", so close is tested with the PiP window's close button
(synthetic mouse events need `mouseEventClickState` 1; a long press on a skip button repeats it).
The PiP window is a panel inside Fernsy's process; screenshots are taken of the screen.

## Risks / Trade-offs

- [PiP may refuse a layer attached to a render synchronizer] → it does not; PiP starts with it.
- [The workaround relies on observed system behaviour (unscaled mirror, stale overlay's class
  name, flush after moving back)] → each part fails harmlessly (picture cropped or partly covered
  as without the workaround); re-check with every major macOS release.
- [Subtitles missing in PiP] → accepted for now (out of scope).
- [Programmatic start requires a user gesture on some systems] → the button is a user gesture;
  the debug hook may need the button pressed via accessibility instead.
