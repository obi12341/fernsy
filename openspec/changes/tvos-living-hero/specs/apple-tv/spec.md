## ADDED Requirements

### Requirement: Living backdrop on Apple TV
While the large entry on Start or the suggestion on Jellyfin's Übersicht has focus, its backdrop
SHALL move slowly (zoom and pan) and cross-fade between the title's backdrops when it has
several. Without focus it SHALL rest. With Reduce Motion it SHALL only cross-fade. No video or
stream SHALL be started for it.

#### Scenario: Focus on the large entry
- **WHEN** the focus rests on "Abspielen" of the large entry
- **THEN** the backdrop zooms and pans slowly, and changes to the title's next backdrop after a few seconds

#### Scenario: Focus in the rows
- **WHEN** the user moves down into "Jetzt live"
- **THEN** the backdrop stops moving and fades as before

#### Scenario: Reduce Motion
- **WHEN** Reduce Motion is on in the Apple TV's settings
- **THEN** the backdrop does not zoom or pan, and only cross-fades between backdrops
