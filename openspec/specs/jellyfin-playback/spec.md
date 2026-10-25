# jellyfin-playback Specification

## Purpose

Plays the films and episodes of the user's Jellyfin server in Fernsy's player – from the
original file whenever possible, transcoded by Jellyfin when Fernsy cannot play it – and keeps
the server's watched state and resume positions up to date.

## Requirements

### Requirement: Play from Jellyfin
Films and episodes SHALL be playable from the film detail, the series detail (each episode and
"Play"/"Resume" for the series), the home rows and context menus, in Fernsy's player window.

#### Scenario: Playing a film
- **WHEN** the user clicks Play on a film
- **THEN** the player window opens and the film starts

#### Scenario: Playing a series
- **WHEN** the user clicks Play on a series
- **THEN** the episode Jellyfin lists under Next Up (or the first episode) starts

### Requirement: Direct play first
Fernsy SHALL play the original file directly (no transcoding) whenever its player supports the
item's container, video, audio and the chosen subtitles; the info overlay names the play method.

#### Scenario: HEVC HDR10 film with TrueHD
- **WHEN** the user plays an HEVC 10-bit HDR10 film with TrueHD audio
- **THEN** it plays directly from the file and the server shows no transcode

### Requirement: Transcode fallback
When an item cannot be played locally, Fernsy SHALL ask Jellyfin for a transcode and play that
instead: known cases are video codecs this Mac cannot decode, including Dolby Vision profile 5
on a Mac that cannot decode it as Dolby Vision; a direct play that fails while opening SHALL be
retried once as a transcode.

#### Scenario: Dolby Vision profile 5
- **WHEN** the user plays a Dolby Vision profile 5 film on a Mac that decodes Dolby Vision
- **THEN** it plays directly as Dolby Vision with correct colours and the server shows no
  transcode

#### Scenario: Dolby Vision profile 5 without Dolby Vision decoding
- **WHEN** this Mac cannot decode a Dolby Vision profile 5 film as Dolby Vision
- **THEN** Jellyfin transcodes it to SDR

#### Scenario: Direct play fails
- **WHEN** the original file cannot be opened by the player
- **THEN** Fernsy switches to a Jellyfin transcode without the user doing anything

### Requirement: Seeking in a transcode
Seeking in a transcoded item SHALL restart the transcode at the new position, with the
timeline and remaining time staying those of the whole item.

#### Scenario: Jumping ahead
- **WHEN** the user seeks to 1:10:00 in a transcoded film
- **THEN** playback continues at 1:10:00 and the timeline shows the film's full length

### Requirement: Resume from the server
Playback SHALL start at the resume position stored on the server, with "Resume" and "From the
beginning" offered in the detail view.

#### Scenario: Started on another client
- **WHEN** a film was stopped at 42:10 in Jellyfin's web client and the user presses Resume in Fernsy
- **THEN** playback starts at 42:10

### Requirement: Report playback to the server
Fernsy SHALL report playback start, progress (about every 10 s and on pause and seek) and stop
with the position, play method and selected tracks, so watched state and resume positions update
on the server; transcodes SHALL be stopped on the server when playback ends. A report rejected
because the session ended SHALL be sent again after the session is renewed, and a stream that
stops for that reason SHALL continue at the same position.

#### Scenario: Stopping halfway
- **WHEN** the user closes the player at 55 % of a film
- **THEN** the server shows the film as partly watched at that position

#### Scenario: Watching to the end
- **WHEN** a film is watched to the end credits
- **THEN** the server marks it as played

#### Scenario: Session ended during a film
- **WHEN** the server ends Fernsy's session while a film plays and the user stops it later
- **THEN** playback continues, and the server shows the position where the user stopped

### Requirement: End reported right away
When an item plays to its end, Fernsy SHALL report the stop with the end position at once, not
only when the player closes, and SHALL NOT report it a second time when the player closes. If
playback continues after the end, a new start SHALL be reported.

#### Scenario: End reported while the player stays open
- **WHEN** an episode ends and the player still shows the next-episode countdown
- **THEN** the server already marks the episode as played and its Next Up shows the following episode

### Requirement: Tracks and external subtitles
The player SHALL offer the item's audio tracks and subtitles, including external subtitle files
Jellyfin knows of; Fernsy never lets the server pick a subtitle track on its own.

#### Scenario: External SRT file
- **WHEN** a film has a German external .srt next to the file
- **THEN** it appears in the subtitle menu and is shown when chosen

### Requirement: Next episode
When an episode ends and a next episode exists, the player SHALL show the next episode with a
countdown (about 10 s) that starts it, and buttons to play it now or cancel.

#### Scenario: Binge watching
- **WHEN** episode 4 ends and the user does nothing
- **THEN** episode 5 starts after the countdown
