## MODIFIED Requirements

### Requirement: Single player window
All playback SHALL happen in one player window (accounts usually allow one stream); closing
it stops playback and closes the stream unless a running recording still uses that channel.

#### Scenario: Closing the player
- **WHEN** the user closes the player window and no recording uses the channel
- **THEN** playback stops and the provider connection is released

#### Scenario: Closing the player during a recording of that channel
- **WHEN** the user closes the player while the channel is being recorded
- **THEN** playback stops and the recording continues on the same connection
