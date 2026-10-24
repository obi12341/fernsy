## MODIFIED Requirements

### Requirement: Event log
Every build SHALL record app events with time, level (info, warning, error, detail) and
category. At least these are recorded: playback start, end and errors; network reconnects
and give-ups; tuner and timeshift problems; recording start, end and failure; catalog,
program guide and Jellyfin loads and failures; Picture in Picture start and stop; playback stalls with their duration.

#### Scenario: Reconnect during live TV
- **WHEN** a live stream's connection drops and is replaced
- **THEN** the log shows a network warning with the reason and the reconnect attempt

#### Scenario: Recording without data
- **WHEN** a recording ends without any data from its channel
- **THEN** the log shows a recordings error naming the show and "no data from the channel"

#### Scenario: Picture stood still
- **WHEN** playback buffers for 2.4 s and then continues
- **THEN** the log shows a player entry "stalled for 2.4 s" (a warning from 3 s on)
