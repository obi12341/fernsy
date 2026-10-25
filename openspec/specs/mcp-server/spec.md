# mcp-server Specification

## Purpose
A local Model Context Protocol server in Fernsy, so the user's AI assistant can read the guide
and viewing history and schedule recordings on the user's behalf.

## Requirements

### Requirement: Local server, off by default
Fernsy SHALL offer an MCP server (Streamable HTTP, JSON responses) under Settings ›
Assistenten, off by default. When on, it SHALL listen only on 127.0.0.1 at a fixed port shown
in Settings, and only while Fernsy runs. Settings SHALL show the endpoint address, a command
for Claude Code, a one-click Claude Desktop extension and, as fallback, the config entry.

#### Scenario: Switching it on
- **WHEN** the user turns on the MCP server in Settings › Assistenten
- **THEN** `http://127.0.0.1:<port>/mcp` answers MCP `initialize` requests and Settings shows how to add it to Claude

#### Scenario: Other devices
- **WHEN** another computer in the network connects to the Mac on that port
- **THEN** the connection is not accepted

### Requirement: Access token
Every request SHALL carry the access token shown in Settings as a bearer token; requests
without it, with a wrong one, or with a browser `Origin` header SHALL be rejected with HTTP 401
or 403. The user SHALL be able to copy the token and to create a new one, which invalidates the
old one at once.

#### Scenario: Missing token
- **WHEN** a local program calls the endpoint without the token
- **THEN** it gets HTTP 401 and no data

#### Scenario: New token
- **WHEN** the user chooses "Neu erzeugen"
- **THEN** clients using the old token are rejected from the next request on

### Requirement: Guide and history tools
The server SHALL offer `find_channels`, `whats_on`, `get_program`, `search_program`,
`recently_watched`, `list_recordings` and `item_info`, apply the app's visibility rules (hidden
channels and categories, adult content per Settings) and give times as ISO 8601 in the Mac's time
zone. `search_program` SHALL search at most 50 channels per call and name them. Films and episodes
SHALL carry their runtime and, once started, the remaining time.

#### Scenario: What's on tonight
- **WHEN** the assistant calls `search_program` for "Tatort" over the favourites
- **THEN** it gets the matching shows with channel, start, end and a show id

#### Scenario: Hidden channel
- **WHEN** a channel is hidden in Fernsy
- **THEN** no tool lists it or its program

#### Scenario: Recently watched with Jellyfin
- **WHEN** the user has a Jellyfin account and calls `recently_watched`
- **THEN** the result lists the recent live channels and Jellyfin's Continue Watching and Next Up items, each with runtime and, if started, remaining time

#### Scenario: Item details
- **WHEN** the assistant calls `item_info` for a Jellyfin episode from Next Up
- **THEN** it gets the series, season, episode, title, runtime and plot

### Requirement: Scheduling through the assistant
`schedule_recording` SHALL schedule a show from the guide with the same padding, overlap and
stream-limit rules as scheduling in the app, and return whether it was planned, planned with
shortened padding, or refused, with the app's explanation. `cancel_recording` SHALL remove only
scheduled recordings and never delete recording files. Scheduled recordings SHALL appear in the
app at once.

#### Scenario: Scheduling a show
- **WHEN** the assistant schedules a show that does not overlap other recordings
- **THEN** it appears under Aufnahmen › Geplant and the tool returns the recording window

#### Scenario: Stream limit
- **WHEN** the account allows one stream and the show overlaps a scheduled recording on another channel
- **THEN** the tool returns "refused" with the reason and nothing is scheduled

#### Scenario: Cancelling a finished recording
- **WHEN** the assistant calls `cancel_recording` for a finished recording
- **THEN** the tool returns an error and the file stays

### Requirement: Playback through the assistant
The tool `play` SHALL start a live channel, an IPTV film or episode, a Jellyfin item or a recording
the way the app does, so another channel switches channels. `now_playing` SHALL report what plays,
its position, duration, remaining time, end clock time and paused state (live: behind-live time and
the current show), and `stop_playback` SHALL stop it. If playing would end a running recording
(stream limit), `play` SHALL change nothing and say why.

#### Scenario: Switching channels
- **WHEN** channel 101 plays and the assistant calls `play` for channel 102
- **THEN** the player switches to channel 102 and `now_playing` reports it

#### Scenario: Recording holds the only stream
- **WHEN** the account allows one stream, a recording runs on channel 101 and the assistant calls `play` for channel 102
- **THEN** nothing changes, the recording continues and the tool returns that the recording holds the stream

#### Scenario: Time left
- **WHEN** a Jellyfin episode of 52 minutes plays at 40 minutes and the assistant calls `now_playing`
- **THEN** it reports position 40:00, duration 52:00, 12 minutes remaining and the clock time it ends

### Requirement: Claude Desktop extension
"Zu Claude Desktop hinzufügen …" SHALL build a desktop extension (`.mcpb`) for the current
endpoint and token and open it in Claude Desktop, or let the user save it when Claude Desktop is
missing. The extension SHALL need no Node.js installation and no further input after installing,
carry a valid semantic version, forward MCP messages to the local endpoint, and answer tool calls
with an explanation while Fernsy or its server is not running.

#### Scenario: Adding Fernsy to Claude Desktop
- **WHEN** the user chooses "Zu Claude Desktop hinzufügen …" with Claude Desktop installed
- **THEN** Claude Desktop shows its install dialog for "Fernsy", and right after installing, without filling in anything, Claude can use Fernsy's tools

#### Scenario: Fernsy closed
- **WHEN** Claude calls a Fernsy tool while Fernsy is not running
- **THEN** the call returns that Fernsy must be open with the MCP server switched on

#### Scenario: New token
- **WHEN** the user creates a new token in Fernsy
- **THEN** the installed extension is refused until Fernsy is added to Claude Desktop again

#### Scenario: Nightly build
- **WHEN** the extension is built by a nightly whose version is "nightly-2026-10-25"
- **THEN** the manifest version is a semantic version such as "0.0.118"

### Requirement: Diagnostics tools
The server SHALL offer `get_log` (current or previous run, oldest first, filtered by minimum level,
category, recent minutes and text, at most 1000 entries) and `playback_diagnostics` (what plays,
the player's state and current statistics, and recent player, network, tuner and timeshift
warnings and errors). Both SHALL return only redacted entries, never credentials or tokens.

#### Scenario: Why does it stutter
- **WHEN** a channel rebuffers and the assistant calls `playback_diagnostics`
- **THEN** it gets the buffer level, rebuffer and reconnect counts with the last reconnect reason, and the related warnings

#### Scenario: Errors of the last hour
- **WHEN** the assistant calls `get_log` with level warning and 60 minutes
- **THEN** it gets the warnings and errors of that hour, oldest first

#### Scenario: No secrets
- **WHEN** a log entry was recorded for a stream URL with credentials
- **THEN** `get_log` returns it with the credentials replaced by "•••"

### Requirement: Player control through the assistant
The server SHALL offer `pause`, `resume` and `seek` (relative seconds, a position, a clock time
in the live buffer, the current show's start, or the live edge) for what plays, within the
player's own limits and answering with the new state. For live TV `now_playing` SHALL report how
far back the buffer reaches (seconds from the current position and as a clock time) and whether
the current show's start is still in it.

#### Scenario: Jump back
- **WHEN** a live channel has been buffered for 10 minutes and the assistant seeks by −120 seconds
- **THEN** playback continues 2 minutes behind live and `now_playing` reports it

#### Scenario: How far back
- **WHEN** the assistant asks `now_playing` while a live channel plays
- **THEN** it reports the rewindable seconds and the clock time the buffer reaches back to

#### Scenario: Start of the show
- **WHEN** the current show started 8 minutes ago, the buffer holds 10 minutes and the assistant seeks to the show's start
- **THEN** playback continues from the show's start

#### Scenario: Beyond the buffer
- **WHEN** the assistant seeks further back than the buffer reaches
- **THEN** playback continues from the oldest buffered moment and the answer says it was limited
