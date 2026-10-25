## MODIFIED Requirements

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
