# Proposal

## Why

On iPhone and iPad a Picture in Picture window opens whenever the user leaves Fernsy, even when
nothing plays. It happens once something was played in that session and the player was closed.
The spec already says PiP starts by itself only "when the user leaves the app while playing", so
this is a bug against `ios-app`. The window is empty or black and has to be closed by hand.

The cause is in `FernsyiOS/PictureInPicture.swift`: the `AVPictureInPictureController` is created
on the first playback, lives for the app's life, and has
`canStartPictureInPictureAutomaticallyFromInline = true` from then on. After the player closes the
engine is `idle`, but `isPaused` stays `false`, so the playback delegate tells iOS that playback
runs, and iOS opens the window on leaving the app.

## What Changes

- Picture in Picture starts by itself only while a channel or an on-demand item actually plays
  (or loads, buffers, is paused) in the full-screen player. Once playback stops, ends or fails,
  leaving the app opens no window.
- The playback delegate reports a stopped engine as paused, so iOS never sees a stopped player as
  running.
- The `ios-app` requirement gets a scenario for leaving the app with nothing playing.

Out of scope: the Mac app's Picture in Picture (no automatic start there), the PiP button in the
player, AirPlay, and returning from PiP; their behavior stays as it is.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ios-app`: "Picture in Picture on iPhone and iPad" gains the scenario that leaving the app with
  nothing playing opens no window.

## Impact

- `FernsyiOS/PictureInPicture.swift` (automatic start follows the engine's status; paused state
  for a stopped engine).
- No change to `FernsyPlayer`, the Apple TV app or the Mac app.
- Verification needs a real device: the iOS simulator has no Picture in Picture.
