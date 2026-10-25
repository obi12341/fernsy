## ADDED Requirements

### Requirement: Next episode in now_playing
While the player shows the next-episode countdown after a Jellyfin episode, `now_playing` SHALL
report the ended state, the next episode (item id, title, season and episode) and the seconds
until it starts. When the user cancelled the countdown, it SHALL report the next episode
without a start time.

#### Scenario: Countdown running
- **WHEN** an episode has ended 3 seconds ago and the assistant calls `now_playing`
- **THEN** the answer says the item ended and that the next episode starts in about 7 seconds, with its item id

#### Scenario: Countdown cancelled
- **WHEN** the user cancelled the countdown and the assistant calls `now_playing`
- **THEN** the answer names the next episode and its item id but no start time

### Requirement: Episode neighbours
`item_info` for a Jellyfin episode SHALL include the previous and the next episode of the series
(item id, season, episode, title), also across season boundaries, and omit them for the first or
last episode.

#### Scenario: Next episode id
- **WHEN** the assistant calls `item_info` for S1E1 of a series with more episodes
- **THEN** the answer contains `next_item_id` of S1E2 and no previous episode

#### Scenario: Across seasons
- **WHEN** the assistant calls `item_info` for the last episode of season 1
- **THEN** the next episode is S2E1

### Requirement: Episode list
The server SHALL offer `list_episodes` for Jellyfin series: without a season, the seasons with
their numbers and episode counts; with a season, its episodes with item id, season and episode
number, title, runtime and watched or in-progress state. The series SHALL be given by series id
or by any of its episodes. Non-Jellyfin items SHALL answer with an error.

#### Scenario: Seasons
- **WHEN** the assistant calls `list_episodes` for a series without a season
- **THEN** the answer lists its seasons with episode counts

#### Scenario: Play season 2 episode 5
- **WHEN** the assistant calls `list_episodes` for season 2 and then `play` with the item id of episode 5
- **THEN** S2E5 plays

#### Scenario: From an episode
- **WHEN** the assistant passes the item id of an episode instead of the series
- **THEN** the answer is for that episode's series

#### Scenario: Not Jellyfin
- **WHEN** the assistant calls `list_episodes` for an IPTV series
- **THEN** the answer is an error saying it is only available for Jellyfin series
