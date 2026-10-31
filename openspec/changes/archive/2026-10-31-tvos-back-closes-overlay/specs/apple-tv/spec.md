## ADDED Requirements

### Requirement: Back in the on-demand and recording players
In the Apple TV player for films, episodes, Jellyfin items, catch-up, cloud recordings and
recordings, Back SHALL close what is on top before it stops playback: first the audio or
subtitle panel, then the next-episode countdown (cancelling it), then the timeline overlay.
Back SHALL stop playback only when none of them shows. Hiding the overlay with Back SHALL NOT
show it again.

#### Scenario: Overlay showing
- **WHEN** a film plays with the timeline overlay showing and the user presses Back
- **THEN** the overlay hides and the film keeps playing

#### Scenario: Nothing showing
- **WHEN** the overlay has hidden and the user presses Back
- **THEN** playback stops and the position is kept

#### Scenario: Track panel open
- **WHEN** the subtitle panel is open and the user presses Back
- **THEN** the panel closes and the film keeps playing

#### Scenario: Next-episode countdown
- **WHEN** an episode ended, the countdown to the next one runs, and the user presses Back
- **THEN** the countdown is cancelled and the player stays open

#### Scenario: Recording player
- **WHEN** a recording plays with its timeline showing and the user presses Back twice
- **THEN** the first press hides the timeline and the second stops playback
