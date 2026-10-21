# timeshift Specification

## Purpose
Lets the user pause and rewind live TV: the tuned channel is kept in a local buffer, and the
player can play anywhere in it or follow the live stream.

## Requirements

### Requirement: Live TV is buffered locally
While a live channel is tuned, the app SHALL keep it in a local buffer for the configured
length (2 minutes, 15, 30, 60 or 120 minutes; default 60) and discard the oldest part beyond
it. The buffer belongs to the tuned channel and is dropped when nobody uses the channel.

#### Scenario: Buffer length
- **WHEN** a channel has been watched for 90 minutes with the setting at 60 minutes
- **THEN** the last 60 minutes can be rewound and older content is gone

#### Scenario: Switching channels
- **WHEN** the user switches to another channel
- **THEN** the previous channel's buffer is discarded (unless a recording still uses that channel)

### Requirement: Pause continues timeshifted
Pausing live TV SHALL keep receiving the channel; resuming SHALL continue from the paused
moment, now behind live.

#### Scenario: Pause for a minute
- **WHEN** the user pauses live TV for one minute and resumes
- **THEN** playback continues from where it was paused and shows about −1:00

### Requirement: Rewind and seek in live TV
For live TV the player SHALL offer a timeline over the buffered range with clock times,
←/→ for ±10 s, ⇧←/⇧→ for ±60 s and a 10 s back button; seeking forward is limited to the
live edge.

#### Scenario: Rewinding two minutes
- **WHEN** the user presses ⇧← twice while watching live
- **THEN** playback jumps two minutes back and the timeline shows the matching clock time

### Requirement: Live state is explicit
While playback follows the live stream, the player SHALL show "LIVE" and keep the timeline
at its end; after a pause or rewind it SHALL show "TIMESHIFT" and the distance to live
(e.g. −1:23). "Live", or moving the timeline to its end, SHALL return to the live edge.

#### Scenario: Bursty provider
- **WHEN** a provider delivers in bursts of several seconds and the user never paused or rewound
- **THEN** the player still shows "LIVE" with the timeline at the end

#### Scenario: Back to live
- **WHEN** the user is 5 minutes behind and clicks "Live"
- **THEN** playback jumps to the live edge and "LIVE" is shown

### Requirement: Following live stays close to live
While following live, playback SHALL never jump on its own. It SHALL keep the distance to the
newest data it settled at after starting – a provider's initial backlog burst is played and
playback is still shown as live. When it falls more than about 12 s further behind than that
distance for several seconds (e.g. after stalls), it SHALL leave the live state and show how far
behind it is; only the user's "Live" action returns to the live edge.

#### Scenario: Backlog at connect
- **WHEN** the provider sends 20 s of backlog spread over the first seconds after the channel
  starts
- **THEN** playback runs on without a jump and the player shows "LIVE"

#### Scenario: Falling further behind
- **WHEN** playback, following live, falls 15 s further behind than where it settled after
  starting
- **THEN** it keeps playing without a jump and the badge changes from "LIVE" to the time behind

#### Scenario: Back to live
- **WHEN** the user clicks the badge showing the time behind
- **THEN** playback goes to the live edge (newest data minus the start lead) and shows "LIVE"

### Requirement: Discontinuities do not interrupt the buffer
Clock jumps in the stream (ad splices, encoder restarts, reconnects to other backends) SHALL
keep the buffer's timeline continuous; content after a backward jump MUST NOT be discarded.

#### Scenario: Ad splice with an earlier clock
- **WHEN** the channel's clock jumps 40 s back during an ad break
- **THEN** playback continues without a gap or freeze

### Requirement: Fallback without timeshift
When a channel's streams cannot be buffered, the player SHALL play the channel directly
without timeshift instead of failing.

#### Scenario: Unsupported stream
- **WHEN** the buffer cannot store a channel's codecs
- **THEN** the channel plays live without pause/rewind
