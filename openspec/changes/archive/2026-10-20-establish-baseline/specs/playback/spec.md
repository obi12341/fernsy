## Purpose

The player window for live channels, movies and episodes: decoding, transport controls,
tracks, resume and robust recovery from network problems typical for IPTV providers.

## ADDED Requirements

### Requirement: Single player window
All playback SHALL happen in one player window (accounts usually allow one stream); closing
it stops playback and closes the stream.

#### Scenario: Closing the player
- **WHEN** the user closes the player window
- **THEN** playback stops and the provider connection is released

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
The player SHALL list all decodable audio tracks and text subtitle tracks, preselect audio
in the user's preferred language, and switch tracks without restarting playback.

#### Scenario: Two audio languages
- **WHEN** a channel has German and English audio and the system language is English
- **THEN** English audio is selected and German can be chosen in the audio menu

### Requirement: Seamless live reconnect
A dropped or stalled live connection SHALL be replaced in place without a visible restart:
replayed content is dropped, timelines of different backends are lined up, and playback
continues where it was. A full restart is tried up to 8 times before an error is shown.

#### Scenario: Connection drops
- **WHEN** the provider closes a live connection while 6 s are buffered
- **THEN** playback continues without a jump or repeated scenes and the info overlay counts a seamless reconnect

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
