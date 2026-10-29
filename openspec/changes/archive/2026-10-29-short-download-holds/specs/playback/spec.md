## MODIFIED Requirements

### Requirement: Dropped connections do not end on-demand playback
When the connection of a film or episode ends before the end of the file – closed by the server
or a proxy (e.g. during a long pause) or failed – the player SHALL continue the download where it
stopped, keeping what is already buffered, without the user noticing. If the server cannot
continue it (no range support, repeated failures), playback SHALL stop with an error, not as
finished. While on-demand media (films, episodes, archived shows) plays, the player SHALL NOT
leave its own download connection idle for more than 15 s, so that steady playback never causes
an interrupted download, whatever the bitrate.

#### Scenario: Long pause
- **WHEN** the user pauses a film for half an hour, the server closes the idle connection, and the
  user continues
- **THEN** the film plays on past the buffered part without stopping

#### Scenario: Connection lost while playing
- **WHEN** the connection of a film drops in the middle
- **THEN** playback continues after a short wait for data, at the same position

#### Scenario: Low-bitrate archive
- **WHEN** an archived show at about 4 Mbit/s plays for ten minutes without the user pausing
- **THEN** the download keeps one connection, the log shows no interrupted download, and the
  info overlay counts no rebuffer
