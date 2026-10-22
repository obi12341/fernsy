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
(←/→) and ±60 s (⇧←/⇧→) and offer a scrub bar. Controls hide after 3 s without activity, but
never while the user drags the scrub bar, the timeshift bar or the volume slider.

#### Scenario: Seeking a movie
- **WHEN** the user presses ⇧→ during a movie
- **THEN** playback continues one minute later

#### Scenario: Holding the scrub bar
- **WHEN** the user drags the scrub bar and keeps the mouse button down for 10 s
- **THEN** the controls stay visible, and they hide 3 s after the button is released

### Requirement: Resume on-demand media
Movies and episodes SHALL resume where they were stopped. Positions under 30 s or within
the last 90 s are not kept.

#### Scenario: Reopening a movie
- **WHEN** the user stopped a movie at 42:10 and plays it again
- **THEN** it starts at 42:10

### Requirement: Audio and subtitle tracks
The player SHALL list all decodable audio tracks and subtitle tracks – text subtitles and bitmap
subtitles (PGS, VobSub, DVB) –, preselect them from the language settings, and switch tracks
without restarting playback. The menus SHALL mark the selected track (or "Off") with a
checkmark, and the control bar SHALL show whether subtitles are on. Bitmap subtitles SHALL be
drawn at their position on the picture; several text subtitles active at the same time SHALL
all be shown.

#### Scenario: Two audio languages
- **WHEN** a channel has German and English audio, the audio setting is "System language" and
  the system language is English
- **THEN** English audio is selected and German can be chosen in the audio menu

#### Scenario: Seeing the selection
- **WHEN** the user opens the audio or subtitle menu
- **THEN** the selected track (or "Off") carries a checkmark, and the subtitle button looks
  different while subtitles are on

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

### Requirement: Dolby Vision
Video streams in MKV or MP4 files with a Dolby Vision profile 5 or profile 8 configuration
SHALL be shown as Dolby Vision through macOS, in HDR on HDR displays and mapped to the display
otherwise. The info overlay SHALL name the Dolby Vision profile and whether it is shown as
Dolby Vision.

#### Scenario: Profile 5 film
- **WHEN** the user plays a Dolby Vision profile 5 file
- **THEN** the colours match the film (no green or pink tint) and the info overlay shows
  "Dolby Vision 5"

#### Scenario: Profile 8 episode
- **WHEN** the user plays a Dolby Vision profile 8.1 episode
- **THEN** it plays as Dolby Vision and seeking, pausing and subtitles work as for HDR10

### Requirement: Dolby Vision fallback
When this Mac cannot decode a stream as Dolby Vision, profile 8 SHALL play its HDR10 base layer
and profile 5 SHALL be reported as not playable locally. Profile 7 SHALL play its HDR10 base
layer.

#### Scenario: Profile 7 film
- **WHEN** the user plays a dual-layer profile 7 film
- **THEN** it plays its HDR10 base layer as before and the overlay says so

#### Scenario: No Dolby Vision decoding
- **WHEN** this Mac cannot decode Dolby Vision and the user plays a profile 8 episode
- **THEN** it plays its HDR10 base layer

### Requirement: Language defaults
Settings SHALL offer a default audio language ("System language" or a fixed language) and a
default subtitle mode ("Off", "Forced only" or a language). Each playback SHALL preselect audio
in that language, else the stream's default track, else the first.

#### Scenario: English audio with German subtitles
- **WHEN** the settings say audio English and subtitles German and a film has both
- **THEN** it starts with English audio and full German subtitles

### Requirement: Subtitle defaults
Subtitles SHALL follow the subtitle mode: none for "Off"; the forced track in the audio's
language for "Forced only"; for a language, its full track, or its forced track when the audio
is already in that language. Without a matching track subtitles SHALL stay off.

#### Scenario: Forced only
- **WHEN** subtitles are set to "Forced only" and a German-dubbed film has a German forced track
- **THEN** only the forced track is shown

#### Scenario: No matching track
- **WHEN** the subtitle language is French and the film has no French subtitles
- **THEN** subtitles stay off and the menu shows "Off" checked

### Requirement: Track choice per series
A track choice the user makes in the player during a series episode (IPTV or Jellyfin) SHALL be
remembered by language for that series and SHALL preselect the tracks of its following
episodes instead of the defaults; films, channels and recordings SHALL always start from the
defaults.

#### Scenario: Binge watching in English
- **WHEN** the user switches episode 1 of a series to English audio and German subtitles and
  then plays episode 2
- **THEN** episode 2 starts with English audio and German subtitles

### Requirement: Dropped connections do not end on-demand playback
When the connection of a film or episode ends before the end of the file – closed by the server
or a proxy (e.g. during a long pause) or failed – the player SHALL continue the download where it
stopped, keeping what is already buffered, without the user noticing. If the server cannot
continue it (no range support, repeated failures), playback SHALL stop with an error, not as
finished.

#### Scenario: Long pause
- **WHEN** the user pauses a film for half an hour, the server closes the idle connection, and the
  user continues
- **THEN** the film plays on past the buffered part without stopping

#### Scenario: Connection lost while playing
- **WHEN** the connection of a film drops in the middle
- **THEN** playback continues after a short wait for data, at the same position

### Requirement: Playback ends only at the real end
On-demand playback SHALL only count as finished near the item's end (within the last 60 s of its
known duration). An earlier end of the stream SHALL be treated as an interruption: the item is
loaded again at the current position once, and if that fails an error is shown. Reports to a
media server (stop position, played state) SHALL never claim the end for such an interruption.

#### Scenario: Stream ends early
- **WHEN** a film's stream ends at 52:10 of 1:58:00
- **THEN** the player does not show "Play Again" but loads the film again at 52:10

#### Scenario: Jellyfin watched state
- **WHEN** a Jellyfin film's stream ends early and the user then closes the player
- **THEN** Jellyfin keeps the film as partly watched at the position where it stopped

### Requirement: Picture in Picture
The player SHALL offer Picture in Picture (button in the controls, key P) for every source. While
it runs, the whole picture plays in the system's floating window and the player window is hidden.
"Back" returns to the player window without interrupting playback; closing the PiP window stops
playback like closing the player window.

#### Scenario: Watching while working
- **WHEN** the user starts Picture in Picture during a live channel
- **THEN** the channel keeps playing in the floating window, shown as live, and the player window disappears

#### Scenario: Controls in the PiP window
- **WHEN** the user uses the PiP window's controls
- **THEN** play/pause works for every source (pausing live TV continues time-shifted) and on-demand media skips back and forward by the system's interval

#### Scenario: Whole picture at any size
- **WHEN** the user resizes the PiP window
- **THEN** the whole picture stays visible and centred, without parts cut off or covered

#### Scenario: Back to the player
- **WHEN** the user clicks "back" in the PiP window
- **THEN** the player window reappears with the picture and playback continues at the same point

#### Scenario: Closing PiP
- **WHEN** the user closes the PiP window
- **THEN** playback stops and the stream is released as when closing the player window
