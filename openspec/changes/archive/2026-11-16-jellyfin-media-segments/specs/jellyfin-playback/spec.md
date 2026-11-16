# Spec Delta

## MODIFIED Requirements

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

## ADDED Requirements

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
