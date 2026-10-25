## ADDED Requirements

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
