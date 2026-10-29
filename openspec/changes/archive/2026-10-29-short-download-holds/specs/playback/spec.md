## ADDED Requirements

### Requirement: On-demand downloads stay connected while playing
While on-demand media (films, episodes, archived shows) plays, the player SHALL NOT leave its own
download connection idle for more than 15 s, so that steady playback never causes an interrupted
download, whatever the bitrate.

#### Scenario: Low-bitrate archive
- **WHEN** an archived show at about 4 Mbit/s plays for ten minutes without the user pausing
- **THEN** the download keeps one connection, the log shows no interrupted download, and the
  info overlay counts no rebuffer
