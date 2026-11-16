# Spec Delta

## MODIFIED Requirements

### Requirement: Next episode in now_playing
While the player shows the next-episode countdown after a Jellyfin episode, `now_playing` SHALL
report the ended state, the next episode (item id, title, season and episode) and the seconds
until it starts. When the user cancelled the countdown, it SHALL report the next episode
without a start time. While the countdown runs during the credits, the item SHALL be reported as
playing, with the next episode and the seconds until it starts.

#### Scenario: Countdown running
- **WHEN** an episode has ended 3 seconds ago and the assistant calls `now_playing`
- **THEN** the answer says the item ended and that the next episode starts in about 7 seconds, with its item id

#### Scenario: Countdown cancelled
- **WHEN** the user cancelled the countdown and the assistant calls `now_playing`
- **THEN** the answer names the next episode and its item id but no start time

#### Scenario: Countdown during the credits
- **WHEN** the credits of an episode play, the countdown started 4 seconds ago, and the assistant calls `now_playing`
- **THEN** the answer says the item is playing and that the next episode starts in about 6 seconds, with its item id
