## ADDED Requirements

### Requirement: Start on Apple TV follows the clock
While Start is shown, Jetzt live SHALL show the show on now with its progress and time left,
moving on to the next show within a minute of the change, and Heute Abend SHALL leave out shows
that ended. The guides of Start's channels SHALL be loaded again when they run short.

#### Scenario: Start left open
- **WHEN** Start stays on screen while a channel's show ends
- **THEN** within a minute its Jetzt live card shows the next show
