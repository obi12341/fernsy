# Proposal

## Why

Planning what to watch and record means scrolling the guide channel by channel. Users who use
Claude (or another MCP client) want to ask in plain words instead: "What's on tonight on my
favourite channels?", "Record the Tatort on Sunday", "What did I watch last on Jellyfin?". A
Model Context Protocol (MCP) server in Fernsy gives these assistants read access to the guide
and the viewing history and lets them schedule recordings, so planning can happen entirely
in the chat.

## What Changes

- Fernsy can run a local MCP server (Streamable HTTP on `127.0.0.1`), switched on in a new
  Settings tab "Assistenten" (off by default). The tab shows the address, an access token with
  "Kopieren" and "Neu erzeugen", and ready-to-paste setup for Claude Code and Claude Desktop.
- Tools (read):
  - `find_channels`: channels by name or category, with ids, favourites marked.
  - `whats_on`: the current and next show for given channels, or for favourites.
  - `get_program`: a channel's guide for a time range (up to the provider's EPG range).
  - `search_program`: shows whose title or description matches, over favourites, recently
    watched or given channels (bounded, see design).
  - `recently_watched`: recently watched live channels, IPTV films with resume positions, and
    Jellyfin "Continue Watching" and "Next Up" when a Jellyfin account exists. IPTV episodes are
    not listed: their resume key does not name the series, so they could not be shown or played.
  - `list_recordings`: running, scheduled and finished recordings with their windows.
- Tools (write):
  - `schedule_recording`: schedules a show from the guide (channel + start or show id), with
    the same padding and stream-limit rules as in the app; returns planned, shortened or refused.
  - `cancel_recording`: removes a scheduled recording (never deletes a recording file).
- Tools (playback):
  - `play`: plays a live channel (switching channels), an IPTV film or episode, a Jellyfin item
    or a recording, the same way as starting it in the app (player window, or the PiP window
    while PiP runs).
  - `now_playing` and `stop_playback`.
  - If playing a channel would end a running recording (stream limit), `play` does nothing and
    returns the reason instead of asking on screen.
- The server only runs while Fernsy runs (like recordings). Every request needs the token.

Out of scope:
- Player controls beyond start and stop (seeking, timeshift, tracks, volume, full screen).
- Deleting recording files, changing settings, favourites or hidden channels.
- Remote access from other devices or from claude.ai in the browser (loopback only).
- A packaged Claude Desktop extension (`.mcpb`); setup uses the documented config snippet.
- An MCP server that works while Fernsy is closed.

## Capabilities

### New Capabilities
- `mcp-server`: the local MCP endpoint, its access control, its tools and their limits.

### Modified Capabilities
<!-- none: scheduling through MCP uses the existing recordings rules unchanged -->

## Impact

- New `Fernsy/MCP/` (HTTP listener on Network.framework, JSON-RPC/MCP handling, tools).
- `Config/Fernsy.entitlements` and `Config/Fernsy-Direct.entitlements`: add
  `com.apple.security.network.server` (App Review note: "local MCP server on 127.0.0.1 for the
  user's own AI assistant, off by default").
- `Fernsy/Views/LoginView.swift` (Settings tab), `SettingsTab`, `AppModel`/`Recorder`/
  `EPGStore`/`JellyfinStore` read access, `AppModel.play(…)` for playback.
- `Fernsy/Localizable.xcstrings`, `DEVELOPMENT.md` (debug switches), README feature list.
