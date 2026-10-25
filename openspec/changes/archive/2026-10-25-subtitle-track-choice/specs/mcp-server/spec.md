## ADDED Requirements

### Requirement: Tracks in item_info
`item_info` for a Jellyfin item SHALL list its audio and subtitle tracks with index, language,
title and whether each is forced, default, external and text (or image).

#### Scenario: Track list
- **WHEN** the assistant calls `item_info` for a film with a forced German, a full German and an English subtitle track
- **THEN** the answer lists the three tracks with their indexes, and only the first is marked forced

## MODIFIED Requirements

### Requirement: Subtitles as text
The server SHALL offer `get_subtitles` for Jellyfin items. It returns the cues of one text
subtitle track with start and end times (seconds and h:mm:ss), optionally limited to a time
range, and names the track returned. Without `item_id` it SHALL use the Jellyfin item that
plays. The server's first preparation of an embedded track SHALL be waited for up to about two
minutes; if that is not enough, the error SHALL say to try again shortly.

#### Scenario: Whole film
- **WHEN** the assistant calls `get_subtitles` for a Jellyfin film with one German text subtitle track
- **THEN** the answer contains every cue of that track with its times and names the track

#### Scenario: Time range
- **WHEN** the assistant calls `get_subtitles` with from 1:10:00 and to 1:20:00
- **THEN** only cues within that range are returned

#### Scenario: Slow first extraction
- **WHEN** the server needs 30 seconds to prepare an embedded track
- **THEN** `get_subtitles` waits and returns the cues

### Requirement: Subtitle track choice
`get_subtitles` SHALL return the track given by `track` (an index from `item_info`). Without
`track` it SHALL use the subtitle track that plays, or the only text track; with several text
tracks it SHALL answer with an error that lists them. When the item has only image subtitles
or none, or is not a Jellyfin item, it SHALL answer with an error that says so.

#### Scenario: By language
- **WHEN** a film has German and English text tracks and the assistant passes the index of the English track from `item_info`
- **THEN** the English cues are returned

#### Scenario: Chosen track
- **WHEN** a film has a forced and a full German track and the assistant passes the full track's index
- **THEN** the full track's cues are returned

#### Scenario: Several tracks, none chosen
- **WHEN** the film has several text tracks, none plays, and the assistant passes no `track`
- **THEN** the answer is an error listing the text tracks with their indexes and flags

#### Scenario: Only image subtitles
- **WHEN** the item has only PGS subtitles
- **THEN** the answer is an error saying there are no text subtitles

#### Scenario: Not Jellyfin
- **WHEN** the assistant calls `get_subtitles` for a live channel, a recording or an IPTV film
- **THEN** the answer is an error saying subtitles are only available for Jellyfin items
