# Proposal

## Why

With Picture in Picture running, the user browses channels in the main window and switches to
another one. Today the hidden player window pops up again (empty, because the video is in the PiP
window) and the PiP window keeps showing the old picture. The first PiP change listed "switching
channels in Fernsy while PiP runs" as out of scope; real use shows it is the natural way to use
PiP (watch while looking through the guide), so it needs defined behaviour.

## What Changes

- Starting something else from the main window while PiP runs (another channel, a film, an
  episode, a recording, a Jellyfin item) plays it in the PiP window; the player window stays
  hidden. "Back" in the PiP window then shows the player window with the new item.
- The PiP window's controls follow the new item (live vs. on-demand, duration).
- While the new item loads, the PiP window shows an animated loading picture with its title
  instead of the old item's last picture (the system shows no loading indicator for this kind of
  PiP source).
- If the new item has no picture (e.g. a radio channel), PiP ends with "back" and the player
  window shows it, because an empty PiP window would be useless.

Out of scope:
- Zapping (channel up/down) from the PiP window itself – the system window offers no such
  controls.
- Starting PiP automatically when something is started while the player window is closed.
- Subtitles in the PiP window (unchanged from the first PiP change).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `playback`: the requirement "Picture in Picture" gains switching to other content while PiP
  runs.

## Impact

- `Fernsy/Views/LibraryView.swift` (opening the player window on a new item),
  `Fernsy/App/AppModel.swift` (shared "PiP is running" state),
  `Fernsy/Views/PlayerScreen.swift` / `Fernsy/Player/PictureInPicture.swift` (switch while PiP
  runs, end PiP for items without picture), a debug switch to start another item while PiP runs,
  README.
- No new entitlement or dependency.
