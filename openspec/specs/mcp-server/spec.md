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

### Requirement: Player in front without taking focus
When the assistant or Siri starts playback, Fernsy SHALL show the player window in front of all
windows, also when it was open behind other windows or minimized, without activating Fernsy, so
keyboard focus stays in the app the user is using. While Picture in Picture runs, no player
window SHALL come forward.

#### Scenario: Playing from the Claude chat
- **WHEN** the user is typing in Claude Desktop and Claude calls `play` for a channel
- **THEN** the player window appears in front of the chat window and the chat keeps keyboard focus

#### Scenario: Player already open behind other windows
- **WHEN** the player window is open behind other apps' windows and the assistant plays another channel
- **THEN** the player window comes in front and shows the new channel

#### Scenario: Picture in Picture
- **WHEN** Picture in Picture runs and the assistant plays a channel
- **THEN** the channel plays in the PiP window and no player window comes forward

### Requirement: Next episode in now_playing
While the player shows the next-episode countdown after a Jellyfin episode, `now_playing` SHALL
report the ended state, the next episode (item id, title, season and episode) and the seconds
until it starts. When the user cancelled the countdown, it SHALL report the next episode
without a start time.

#### Scenario: Countdown running
- **WHEN** an episode has ended 3 seconds ago and the assistant calls `now_playing`
- **THEN** the answer says the item ended and that the next episode starts in about 7 seconds, with its item id

#### Scenario: Countdown cancelled
- **WHEN** the user cancelled the countdown and the assistant calls `now_playing`
- **THEN** the answer names the next episode and its item id but no start time

### Requirement: Episode neighbours
`item_info` for a Jellyfin episode SHALL include the previous and the next episode of the series
(item id, season, episode, title), also across season boundaries, and omit them for the first or
last episode.

#### Scenario: Next episode id
- **WHEN** the assistant calls `item_info` for S1E1 of a series with more episodes
- **THEN** the answer contains `next_item_id` of S1E2 and no previous episode

#### Scenario: Across seasons
- **WHEN** the assistant calls `item_info` for the last episode of season 1
- **THEN** the next episode is S2E1

### Requirement: Episode list
The server SHALL offer `list_episodes` for Jellyfin series: without a season, the seasons with
their numbers and episode counts; with a season, its episodes with item id, season and episode
number, title, runtime and watched or in-progress state. The series SHALL be given by series id
or by any of its episodes. Non-Jellyfin items SHALL answer with an error.

#### Scenario: Seasons
- **WHEN** the assistant calls `list_episodes` for a series without a season
- **THEN** the answer lists its seasons with episode counts

#### Scenario: Play season 2 episode 5
- **WHEN** the assistant calls `list_episodes` for season 2 and then `play` with the item id of episode 5
- **THEN** S2E5 plays

#### Scenario: From an episode
- **WHEN** the assistant passes the item id of an episode instead of the series
- **THEN** the answer is for that episode's series

#### Scenario: Not Jellyfin
- **WHEN** the assistant calls `list_episodes` for an IPTV series
- **THEN** the answer is an error saying it is only available for Jellyfin series

### Requirement: Snapshot of the player
The server SHALL offer `snapshot`, which returns the picture the player currently shows as an
image (at most 1280 pixels wide) with the item and its position, or the clock time for live TV.
It SHALL NOT open a connection or change playback, so it works for every kind of item that
plays, including IPTV films and live TV without timeshift.

#### Scenario: Picture of a film
- **WHEN** a Jellyfin film plays at 1:14:30 and the assistant calls `snapshot`
- **THEN** the answer contains an image of the shown picture and the position 1:14:30, and playback continues unchanged

#### Scenario: Live TV
- **WHEN** a live channel plays 2 minutes behind live and the assistant calls `snapshot`
- **THEN** the answer contains the picture and the clock time of the shown moment

#### Scenario: Nothing to show
- **WHEN** no player is open, or no picture has been shown yet, and the assistant calls `snapshot`
- **THEN** the answer is an error that says so

### Requirement: Contact sheet of a time range
The server SHALL offer `frames`: one image with `count` (default 24, 4–48) evenly spaced
stills from `from`–`to` (default the whole item or buffer), each labelled with its position or
live clock time, plus a list of those times. A still MAY come from the nearest earlier
keyframe, labelled with that time. It SHALL NOT change what the player shows; without
`item_id` it uses what plays.

#### Scenario: Coarse to fine
- **WHEN** the assistant calls `frames` for a 2-hour Jellyfin film with count 24, then for 1:12:00–1:16:00 with count 24
- **THEN** the first sheet shows stills about every 5 minutes, the second about every 10 seconds, each labelled with its position, and the player is not affected

#### Scenario: Labels show the real time
- **WHEN** a requested time falls between two keyframes
- **THEN** the still comes from the earlier keyframe and its label and list entry show that keyframe's time

### Requirement: Sources of contact sheets
`frames` SHALL work for Jellyfin items, recordings (also while they are still recording) and
the timeshift buffer of a live channel that plays or records. For live TV it SHALL read only
the local buffer and open no connection to the provider. For IPTV films and episodes, and for
live channels without a buffer, it SHALL answer with an error that explains why.

#### Scenario: Live buffer
- **WHEN** a live channel has been buffered for 20 minutes and the assistant calls `frames` for it without a range
- **THEN** the sheet covers the buffered 20 minutes with clock-time labels, and no additional stream is opened

#### Scenario: Running recording
- **WHEN** a recording has been running for 10 minutes and the assistant calls `frames` for it
- **THEN** the sheet covers the 10 recorded minutes

#### Scenario: IPTV film
- **WHEN** the assistant calls `frames` for an IPTV film or episode
- **THEN** the answer is an error explaining that this would need a second stream, and suggests `snapshot`

#### Scenario: Live channel not tuned
- **WHEN** the assistant calls `frames` for a live channel that is neither playing nor recording
- **THEN** the answer is an error saying the channel has no buffer

### Requirement: Subtitles as text
The server SHALL offer `get_subtitles` for Jellyfin items. It returns the cues of one text
subtitle track with start and end times (seconds and h:mm:ss), optionally limited to a time
range, and lists the item's text subtitle tracks, naming the one returned. Without `item_id`
it SHALL use the Jellyfin item that plays.

#### Scenario: Whole film
- **WHEN** the assistant calls `get_subtitles` for a Jellyfin film with a German text subtitle track
- **THEN** the answer contains every cue of that track with its times and names the track

#### Scenario: Time range
- **WHEN** the assistant calls `get_subtitles` with from 1:10:00 and to 1:20:00
- **THEN** only cues within that range are returned

### Requirement: Subtitle track choice
`get_subtitles` SHALL select the track by `language` (language code or part of the title) when
given, otherwise the track that plays, otherwise the first text track. When the item has only
image subtitles or none, or is not a Jellyfin item, it SHALL answer with an error that says so.

#### Scenario: By language
- **WHEN** a film has German and English text tracks and the assistant passes `language: "eng"`
- **THEN** the English cues are returned

#### Scenario: Only image subtitles
- **WHEN** the item has only PGS subtitles
- **THEN** the answer is an error saying there are no text subtitles

#### Scenario: Not Jellyfin
- **WHEN** the assistant calls `get_subtitles` for a live channel, a recording or an IPTV film
- **THEN** the answer is an error saying subtitles are only available for Jellyfin items

### Requirement: Image results
Tool results that carry a picture SHALL return it as MCP image content (JPEG) together with
the text result. The text and structured content SHALL describe the image (item, times) without
embedding the image data again.

#### Scenario: Image next to text
- **WHEN** the assistant calls `snapshot` or `frames`
- **THEN** the result's content holds one JPEG image and one text part, and the structured content holds the times but no image data
