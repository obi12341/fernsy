# Proposal

## Why

When playback stutters, freezes or fails, the answer is in Fernsy's event log (reconnects,
rebuffers, decoder flushes, provider errors) and in the player's live statistics (buffer level,
bitrate, dropped frames, decode failures). Today an assistant connected over MCP cannot see
either, so "why does the picture stutter?" gets a guess. Giving the user's own assistant read
access lets it answer from the facts.

## What Changes

- New MCP tool `get_log`: entries of the current run (or the previous one), oldest first, with
  time, level, category and message; filters for minimum level (default info), category, the last
  N minutes (default 30), a text search, and a limit (default 200, at most 1000). Entries are the
  already redacted ones (no credentials, tokens or Xtream path credentials).
- New MCP tool `playback_diagnostics`: what plays and the player's current statistics (state,
  buffer seconds, bitrate, dropped frames, decode failures, rebuffers, seamless reconnects, last
  reconnect reason and time, restarts, codec, resolution, frame rate, decoder, play method), plus
  the warnings and errors of the last 10 minutes from the player, network, tuner and timeshift
  categories.
- The app-log requirement "never sent anywhere" gets its one exception: the log is handed to the
  user's own assistant through the local MCP server when the user has switched it on.

Out of scope:
- Clearing the log, changing log levels or saving files over MCP.
- Sending logs anywhere else (support upload, crash reporting).

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `mcp-server`: new requirement for the diagnostics tools.
- `app-log`: "Log kept across one restart" allows reading through the user's local MCP server.

## Impact

- `Fernsy/MCP/MCPTools.swift` (two tools), `AppLog` (a filtered read of current/previous run).
- `Fernsy/Views/LoginView.swift` (Assistenten footnote mentions the log), `Localizable.xcstrings`.
- `DEVELOPMENT.md`; the App Review note in `docs/app-store.md` mentions log access.
