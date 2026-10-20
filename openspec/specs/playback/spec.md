# playback Specification

## Purpose
The player window for live channels, movies and episodes: decoding, transport controls,
tracks, resume and robust recovery from network problems typical for IPTV providers.

## Requirements

### Requirement: Single player window
All playback SHALL happen in one player window (accounts usually allow one stream); closing
it stops playback and closes the stream unless a running recording still uses that channel.

#### Scenario: Closing the player
- **WHEN** the user closes the player window and no recording uses the channel
- **THEN** playback stops and the provider connection is released

#### Scenario: Closing the player during a recording of that channel
- **WHEN** the user closes the player while the channel is being recorded
- **THEN** playback stops and the recording continues on the same connection

### Requirement: Hardware decoding and deinterlacing
Video SHALL be decoded with VideoToolbox where possible (software otherwise), up to 4K and
HDR; interlaced TV SHALL be deinterlaced to double frame rate on the GPU (CPU fallback).

#### Scenario: Interlaced HD channel
- **WHEN** a 1080i channel plays
- **THEN** it is shown deinterlaced at 50 fps and the info overlay names the deinterlacer

### Requirement: Transport controls and keyboard
The player SHALL offer play/pause (Space), mute (M), volume (+/−, remembered), full screen
(F, double-click, Esc to leave) and technical info (I). On-demand media SHALL seek ±10 s
(←/→) and ±60 s (⇧←/⇧→) and offer a scrub bar. Controls hide after 3 s without activity.

#### Scenario: Seeking a movie
- **WHEN** the user presses ⇧→ during a movie
- **THEN** playback continues one minute later

### Requirement: Resume on-demand media
Movies and episodes SHALL resume where they were stopped. Positions under 30 s or within
the last 90 s are not kept.

#### Scenario: Reopening a movie
- **WHEN** the user stopped a movie at 42:10 and plays it again
- **THEN** it starts at 42:10

### Requirement: Audio and subtitle tracks
The player SHALL list all decodable audio tracks and subtitle tracks – text subtitles and bitmap
subtitles (PGS, VobSub, DVB) –, preselect audio in the user's preferred language, and switch
tracks without restarting playback. Bitmap subtitles SHALL be drawn at their position on the
picture; several text subtitles active at the same time SHALL all be shown.

#### Scenario: Two audio languages
- **WHEN** a channel has German and English audio and the system language is English
- **THEN** English audio is selected and German can be chosen in the audio menu

#### Scenario: PGS subtitles of a Blu-ray remux
- **WHEN** the user chooses a PGS subtitle track
- **THEN** the subtitles appear as on the disc, at their position and in time with the picture

#### Scenario: Two speakers at once
- **WHEN** two text subtitle cues overlap in time
- **THEN** both lines are shown

### Requirement: Seamless live reconnect
A dropped or stalled live connection SHALL be replaced in place without a visible restart:
replayed content is dropped, timelines of different backends are lined up, and playback
continues where it was. A full restart is tried up to 8 times before an error is shown.

#### Scenario: Connection drops
- **WHEN** the provider closes a live connection while 6 s are buffered
- **THEN** playback continues without a jump or repeated scenes and the info overlay counts a seamless reconnect

#### Scenario: New connection replays the server's buffer
- **WHEN** the new connection starts with several seconds the player already played
- **THEN** those packets are dropped and counted as duplicates in the info overlay

#### Scenario: New connection lands on a backend with another clock
- **WHEN** the reconnect is answered by a backend whose timestamps differ by minutes for the same content
- **THEN** the offset is measured from identical packets and playback continues without a jump

#### Scenario: Real gap in the content
- **WHEN** the new connection continues later than where playback was (content was missed)
- **THEN** gaps under 10 s are closed on the timeline, video resumes at the next keyframe, and larger jumps resynchronize playback

#### Scenario: Stalled connection
- **WHEN** no data arrives for 4 s while the player has less than 4 s left (or for 30 s regardless)
- **THEN** the connection is replaced, first via the same edge host, then via the provider's load balancer

#### Scenario: Several quick reconnects
- **WHEN** a provider accepts and drops connections several times within seconds
- **THEN** packets still arriving from older connections are placed with their own connection's offset, and the source gives up after 8 attempts in one incident

### Requirement: Broken audio streams
Live streams whose audio FFmpeg cannot identify (an endless AAC PES, often declared as AC-3)
SHALL still play with sound by demuxing that audio directly; the PID is remembered per channel.

#### Scenario: Restream with an unidentified audio PID
- **WHEN** a channel's only audio stream has no parameters after probing
- **THEN** the channel plays with AAC audio labeled as repaired from the TS stream

### Requirement: Missing audio indicator
When a channel has no audio track, or its audio stops delivering for more than 0.7 s while
the picture continues, the player SHALL show a badge saying so.

#### Scenario: Audio gap
- **WHEN** a channel's audio pauses for two seconds while video plays
- **THEN** "No sound from the channel – waiting for sound …" is shown until audio returns

### Requirement: Technical information overlay
The info overlay SHALL show container, codecs, resolution, frame rate, decoder, pixel
format, dynamic range, deinterlacing, audio format, bit rate, buffer levels, connection and
startup time, reconnects, rebuffers, dropped frames and a two-minute buffer chart.

#### Scenario: Pressing I
- **WHEN** the user presses I during playback
- **THEN** the overlay appears and updates once per second
