## MODIFIED Requirements

### Requirement: Recording files
Recordings SHALL be saved as MPEG-TS files in `~/Movies/Fernsy` named
"<Channel> – <Title> (<yyyy-MM-dd HH.mm>).ts", where <Channel> is the cleaned channel name
followed by its country tag in parentheses when there is one, playable in Fernsy and other
players, also while still recording.

#### Scenario: Watching a running recording
- **WHEN** the user plays a recording that is still running
- **THEN** it plays from the start and can be watched up to the current moment

#### Scenario: File name with a country tag
- **WHEN** the show "Tatort" on "DE: Das Erste HD" is recorded on 2026-10-24 at 20:15
- **THEN** the file is named "Das Erste (DE) – Tatort (2026-10-24 20.15).ts"
