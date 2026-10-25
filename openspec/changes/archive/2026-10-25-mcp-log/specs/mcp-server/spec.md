## ADDED Requirements

### Requirement: Diagnostics tools
The server SHALL offer `get_log` (current or previous run, oldest first, filtered by minimum level,
category, recent minutes and text, at most 1000 entries) and `playback_diagnostics` (what plays,
the player's state and current statistics, and recent player, network, tuner and timeshift
warnings and errors). Both SHALL return only redacted entries, never credentials or tokens.

#### Scenario: Why does it stutter
- **WHEN** a channel rebuffers and the assistant calls `playback_diagnostics`
- **THEN** it gets the buffer level, rebuffer and reconnect counts with the last reconnect reason, and the related warnings

#### Scenario: Errors of the last hour
- **WHEN** the assistant calls `get_log` with level warning and 60 minutes
- **THEN** it gets the warnings and errors of that hour, oldest first

#### Scenario: No secrets
- **WHEN** a log entry was recorded for a stream URL with credentials
- **THEN** `get_log` returns it with the credentials replaced by "•••"
