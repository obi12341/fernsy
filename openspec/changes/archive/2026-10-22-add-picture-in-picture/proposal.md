# Proposal

## Why

The user wants to keep watching (live TV, a film, a Jellyfin episode) in a small floating window
while working in other apps. macOS has Picture in Picture built in, and since macOS 12 it can
take an `AVSampleBufferDisplayLayer` as its source – exactly the layer Fernsy's player renders
into for every source.

## What Changes

- A Picture in Picture button in the player controls (and the key P) moves the video into the
  system's floating PiP window; the player window disappears meanwhile (decided: like Safari and
  the TV app).
- In the PiP window: play/pause, skipping back/forward for films (the system's interval, 10 s;
  live TV shows as live without skip buttons, pausing it continues time-shifted), "back to
  Fernsy" and close.
- "Back" brings the player window back with playback continuing; closing PiP stops playback like
  closing the player window.
- Works for all sources (IPTV live/timeshift, films, series, recordings, Jellyfin, Dolby Vision).

Out of scope:
- Subtitles inside the PiP window (they are drawn by Fernsy's own overlay, which PiP does not
  show).
- Zapping channels from the PiP window; switching channels in Fernsy while PiP runs.
- Starting PiP automatically when the window is minimised or the app goes to the background.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `playback`: new requirement "Picture in Picture" (the hidden player window during PiP is still
  the single player window, so "Single player window" stays as it is).

## Impact

- `Fernsy/Player/PlayerEngine.swift` or a new `Fernsy/Player/PictureInPicture.swift`
  (`AVPictureInPictureController` with a sample-buffer content source and playback delegate),
  `Fernsy/Views/PlayerScreen.swift` (button, key, hiding/showing the window, closing),
  `Localizable.xcstrings`, `README.md`.
- No new entitlement; AVKit is part of the system.
