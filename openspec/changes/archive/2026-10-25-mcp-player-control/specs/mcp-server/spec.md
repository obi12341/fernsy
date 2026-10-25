## ADDED Requirements

### Requirement: Player control through the assistant
The server SHALL offer `pause`, `resume` and `seek` (relative seconds, a position, a clock time
in the live buffer, the current show's start, or the live edge) for what plays, within the
player's own limits and answering with the new state. For live TV `now_playing` SHALL report how
far back the buffer reaches (seconds from the current position and as a clock time) and whether
the current show's start is still in it.

#### Scenario: Jump back
- **WHEN** a live channel has been buffered for 10 minutes and the assistant seeks by −120 seconds
- **THEN** playback continues 2 minutes behind live and `now_playing` reports it

#### Scenario: How far back
- **WHEN** the assistant asks `now_playing` while a live channel plays
- **THEN** it reports the rewindable seconds and the clock time the buffer reaches back to

#### Scenario: Start of the show
- **WHEN** the current show started 8 minutes ago, the buffer holds 10 minutes and the assistant seeks to the show's start
- **THEN** playback continues from the show's start

#### Scenario: Beyond the buffer
- **WHEN** the assistant seeks further back than the buffer reaches
- **THEN** playback continues from the oldest buffered moment and the answer says it was limited
