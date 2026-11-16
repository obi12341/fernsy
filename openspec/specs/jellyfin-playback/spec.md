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
When an episode reaches its final credits and a next episode exists, the player SHALL show the
next episode with a countdown (about 10 s) that starts it, and buttons to play it now or to watch
the credits. Without known credits the card SHALL appear when the episode ends, with play now and
cancel. The card SHALL show the episode's image, series, season and episode, and title.

#### Scenario: Binge watching
- **WHEN** episode 4 ends and the user does nothing
- **THEN** episode 5 starts after the countdown

#### Scenario: Credits known
- **WHEN** episode 4 has a credits segment from 40:58 to its end at 45:35 and playback reaches 40:58
- **THEN** the card for episode 5 appears with the countdown while the credits play, and episode 5 starts after it

#### Scenario: Watching the credits
- **WHEN** the card shows during the credits and the user chooses Watch Credits
- **THEN** the card closes, the credits play to the end, and no card appears again at the end

#### Scenario: Scene after the credits
- **WHEN** the final credits end 26 s before the end of the file and playback reaches them
- **THEN** the card offers the next episode without a countdown, and the episode keeps playing

#### Scenario: Preview after the credits
- **WHEN** the credits are followed directly by a preview segment that runs to the end of the file
- **THEN** the card appears with the countdown at the start of the credits

#### Scenario: False credits mid-episode
- **WHEN** an episode has a 16 s credits segment four minutes before its final credits
- **THEN** no card appears at the short segment, only at the final credits

#### Scenario: No credits known
- **WHEN** an episode has neither a credits segment nor a credits chapter
- **THEN** the card appears when the episode ends, as without segments

### Requirement: Media segments from the server
When an episode starts, Fernsy SHALL read its media segments (intro, recap, credits, preview)
from the Jellyfin server. When the server has no credits segment, an embedded chapter named as
credits ("Credits", "End Credits", "Ending", "Abspann") SHALL mark the start of the credits.
A server without segments or chapters SHALL play as before.

#### Scenario: Segments from Intro Skipper
- **WHEN** the server's Intro Skipper plugin found an intro and credits in an episode
- **THEN** Fernsy offers to skip the intro and shows the next episode at the credits

#### Scenario: Credits chapter only
- **WHEN** an episode has no segments but a chapter "Credits" at 22:40
- **THEN** the next-episode card appears at 22:40

#### Scenario: Server without segment support
- **WHEN** the server answers the segment request with an error or an empty list
- **THEN** the episode plays normally and the card appears at its end

### Requirement: Skip intro and recap
While an intro or recap segment plays, the player SHALL show "Skip Intro" or "Skip Recap"; using
it SHALL continue playback at the segment's end. The button SHALL disappear when the segment ends
or playback moves outside it.

#### Scenario: Skipping the intro
- **WHEN** an episode's intro runs from 6:30 to 8:00 and the user chooses Skip Intro at 6:45
- **THEN** playback continues at 8:00

#### Scenario: Recap at the start
- **WHEN** an episode starts with a recap from 0:00 to 0:38
- **THEN** the player shows Skip Recap until 0:38

#### Scenario: Seeking past the intro
- **WHEN** the user seeks from inside the intro to 20:00
- **THEN** the skip button disappears

### Requirement: Played when leaving in the credits
When the user moves on to the next episode or closes the player during an episode's final
credits, Fernsy SHALL mark the episode as played on the server, even when its position is below
the server's played threshold.

#### Scenario: Next episode from the credits
- **WHEN** the user chooses Play Now at 40:58 of a 45:35 episode whose credits start at 40:58
- **THEN** the server shows the episode as played and Next Up names the following episode

#### Scenario: Closing during the credits
- **WHEN** the user closes the player during the final credits
- **THEN** the server shows the episode as played

#### Scenario: Closing before the credits
- **WHEN** the user closes the player two minutes before the credits
- **THEN** the server keeps the episode partly watched at that position

### Requirement: Still watching
After three episodes in a row that the countdown started without any input from the user in
between, the next card SHALL ask "Are you still watching?" with a button to continue and SHALL
NOT start the next episode by itself. Any input in the player SHALL reset the count.

#### Scenario: Asleep on the couch
- **WHEN** the countdown has started three episodes in a row with no input and the third reaches its credits
- **THEN** the card asks whether the user is still watching, and nothing starts by itself

#### Scenario: Pausing in between
- **WHEN** the user paused once during the second auto-started episode
- **THEN** the count starts again and the next cards keep counting down

### Requirement: Next-episode and skip settings
Settings › Jellyfin Server SHALL offer "Play Next Episode Automatically" (on by default) and
"Skip Intros and Recaps" with Show Button (default), Automatically and Never. With automatic play
off the card SHALL appear without a countdown. Automatic skipping SHALL jump over the segment and
briefly say so; Never SHALL show no skip button.

#### Scenario: Automatic play off
- **WHEN** the setting is off and an episode reaches its credits
- **THEN** the card shows the next episode with Play Now and no countdown

#### Scenario: Skipping automatically
- **WHEN** skipping is set to Automatically and an intro begins
- **THEN** playback jumps to the intro's end and the player briefly shows that the intro was skipped
