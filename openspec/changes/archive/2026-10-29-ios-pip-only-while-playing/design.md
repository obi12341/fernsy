# Design

## Context

`PictureInPicture.shared` (ios-app design 5) creates one `AVPictureInPictureController` for the
engine's `AVSampleBufferDisplayLayer` the first time `PlayerView` appears and keeps it for the
app's life, because the model has one engine for the app's life. Automatic start
(`canStartPictureInPictureAutomaticallyFromInline`) is set once to `true`. iOS starts PiP on
leaving the app when the controller allows it and the playback delegate reports the content as
not paused. `PlayerEngine.stop()` sets `status = .idle` and clears `media`, but leaves `isPaused`
as it was (`false` after normal playback), and `pictureInPictureControllerIsPlaybackPaused`
returns `engine.isPaused`.

## Goals / Non-Goals

**Goals:**
- Automatic PiP only while the full-screen player has something to show.
- A stopped engine never reads as "playing" to AVKit.

**Non-Goals:**
- Changing the PiP button, the restore path, or closing PiP (which stops playback).
- The Mac app's PiP.
- Changing `PlayerEngine` (shared with the Mac and Apple TV apps).

## Decisions

1. **Automatic start follows the engine's status.** `attach` subscribes to `engine.$status` and sets
   `canStartPictureInPictureAutomaticallyFromInline` to `true` for `loading`, `playing`, `paused`
   and `buffering`, and to `false` for `idle`, `ended` and `failed`, logging the switch under
   `.pip`. The engine is what the controller already observes and what stops on every close path
   (swipe down, close button, closing the PiP window, channel errors), so one subscription covers
   them all.
   - Rejected: switching it in `PlayerView.onAppear`/`onDisappear`. The view disappears when PiP
     starts too, and the cover's dismissal timing already caused the orientation bug; status is
     the plain fact.
   - Rejected: tearing the controller down on stop and creating it again on the next play. AVKit
     needs the controller to exist before the app leaves; re-creating it per play adds churn and
     a window where `isPictureInPicturePossible` is still false.
   - Rejected: following `TVModel.playing`/`playingVOD`. That is the model's intent, not whether
     the layer has a picture; the status also turns off for a failed stream.
2. **A stopped engine reads as paused.** `pictureInPictureControllerIsPlaybackPaused` returns
   `true` when the status is `idle`, `ended` or `failed`, else `engine.isPaused`. A second guard,
   in case the system asks before the status subscription has run.

3. **Returning keeps playing.** Found on the iPad: after "back" in the window, the player came
   back paused (position stood still, no pause from the app's controls in the log). The playback
   delegate ignores `setPlaying(false)` between `restoreUserInterface…` and `didStop` and logs it;
   if the engine played when "back" was tapped and is paused once PiP has stopped, playback
   continues. This is the existing "Back from Picture in Picture" scenario ("still playing"), so
   the spec text does not change.
   - Rejected: always unpausing after a restore. A user who paused in the window before tapping
     "back" expects it to stay paused.

## Risks / Trade-offs

- **PiP during `loading`:** leaving the app while a channel still loads opens the window with the
  loading card, as today. Kept on purpose: the user did start playback.
- **No simulator check:** `isPictureInPictureSupported()` is false in the simulator, so the
  controller is never made there. Verification runs on the real iPad (Release build, ipad-release
  recipe) against the demo server.
