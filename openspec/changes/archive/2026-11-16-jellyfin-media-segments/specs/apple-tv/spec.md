# Spec Delta

## ADDED Requirements

### Requirement: Next episode and skipping on Apple TV
Jellyfin episodes SHALL show the next episode at their credits and offer to skip intros and
recaps under the Mac's rules. Play Now SHALL have focus when the card appears; while the skip
button shows, Select SHALL skip.

#### Scenario: Next episode at the credits
- **WHEN** a Jellyfin episode reaches its final credits and the next one exists
- **THEN** the player shows the next episode with its image and a countdown, with Play Now focused

#### Scenario: Skipping the intro with Select
- **WHEN** a Jellyfin episode's intro plays and the user presses Select
- **THEN** playback continues at the end of the intro

### Requirement: Back on the next-episode card and the skip button
During the credits, Back on the next-episode card SHALL close the card and keep the credits
playing, with no card again at the end. The skip button SHALL NOT take part in Back: with only
the skip button showing, Back stops playback.

#### Scenario: Next-episode card during the credits
- **WHEN** the next-episode card shows during the credits and the user presses Back
- **THEN** the card closes, the credits keep playing, and no card appears again at the end

#### Scenario: Skip button showing
- **WHEN** only the Skip Intro button shows and the user presses Back
- **THEN** playback stops and the position is kept
