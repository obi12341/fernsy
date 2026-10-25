# Proposal

## Why

When playback is started from outside Fernsy (an MCP `play`, Siri's "Öffne ZDF in Fernsy"), the
player window often appears behind the window of the app the user is in, for example the Claude
chat. Fernsy is not the active app at that moment, and macOS places a new window of a background
app behind the active app's windows; an already open player window behind other windows is not
brought forward at all (`PlayerWindow.show` returns early when the window is visible). The MCP
design intended "brings the player to the front", which was never implemented.

## What Changes

- Playback started by MCP or Siri brings the player window in front of all windows, also when it
  was already open behind others or minimized, without activating Fernsy: keyboard focus stays in
  the app the user is in (the user's choice "A").
- Picture in Picture: unchanged (no player window comes forward while PiP runs).
- Starting playback inside Fernsy: unchanged.

Out of scope:
- Activating Fernsy or taking focus (rejected variant "B").
- Full-screen spaces: a player window in its own full-screen space is shown by switching to that
  space only if macOS does so on ordering front; no extra handling.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `mcp-server`: new requirement that playback started by the assistant shows the player in front
  without taking focus (shared with Siri's open action).

## Impact

- `PlayerWindow` in `Fernsy/MCP/MCPTools.swift` (`show`), the player window's appearance hook in
  `PlayerScreen` for a newly opened window.
