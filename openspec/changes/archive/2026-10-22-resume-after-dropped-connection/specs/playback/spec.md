## ADDED Requirements

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
