## MODIFIED Requirements

### Requirement: Rewind and seek in live TV
For live TV the player SHALL offer a timeline over the buffered range with clock times
below and the shows' boundaries and titles above, ←/→ for ±10 s, ⇧←/⇧→ for ±60 s and
−10/+10 buttons; seeking forward is limited to the live edge.

#### Scenario: Rewinding two minutes
- **WHEN** the user presses ⇧← twice while watching live
- **THEN** playback jumps two minutes back and the timeline shows the matching clock time

#### Scenario: Where a show began
- **WHEN** the buffer reaches back across the start of the current show
- **THEN** the timeline marks that start and shows the show's title next to it

### Requirement: Live state is explicit
While playback follows the live stream, the player SHALL show a red "LIVE" badge and keep
the timeline at its end; after a pause or rewind it SHALL show the distance to live
(e.g. −1:23) with a red "ZU LIVE" button. That button, or moving the timeline to its end,
SHALL return to the live edge.

#### Scenario: Bursty provider
- **WHEN** a provider delivers in bursts of several seconds and the user never paused or rewound
- **THEN** the player still shows "LIVE" with the timeline at the end

#### Scenario: Back to live
- **WHEN** the user is 5 minutes behind and clicks "ZU LIVE"
- **THEN** playback jumps to the live edge and "LIVE" is shown
