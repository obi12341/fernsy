# Proposal

## Why

When the player is in full screen and the user switches to another app, coming back with ⌘-Tab
or the Dock shows the library (channel list) window on the desktop instead of the full-screen
player. That is standard macOS behaviour: an app is activated on the current Space if it has a
window there, and Fernsy's library window is on the desktop. For a player it is the wrong
result, because full-screen viewers have the player's own channel overlay and rarely need the
library at that moment.

## What Changes

- While the player window is in full screen, Fernsy hides its library window(s). With no
  Fernsy window left on the desktop, macOS switches to the full-screen Space when Fernsy is
  activated (⌘-Tab, Dock, `open`).
- When the player leaves full screen, or closes while in full screen, the hidden library
  windows come back where they were, behind the player.
- Asking for the library while it is hidden (menu bar "Fernsy öffnen", Siri "Suche … in
  Fernsy", the window menu) shows the hidden window instead of opening a second one.

### Out of scope

- Changing macOS's Space switching or forcing the player to the front on every activation
  (variant B, rejected: a deliberate click on the library would be pulled into full screen).
- Picture in Picture (not full screen; unchanged).
- The log window and Settings.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playback`: the library is hidden while the player is in full screen.

## Impact

- `Fernsy/Views/PlayerScreen.swift` (full-screen notifications, close), a small helper for the
  library windows (`Fernsy/App/`), `MenuBarSupport.showLibrary` and `PlayerWindow.showLibrary`
  (restore a hidden window).
- `DEVELOPMENT.md` (window notes).
