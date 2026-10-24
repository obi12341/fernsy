## MODIFIED Requirements

### Requirement: Menu bar item
The app SHALL show a menu bar item (TV symbol, with a red dot while recording) listing
running recordings with their end time and a stop action, the next scheduled recording,
"Open Fernsy", "Show Recordings" and "Quit Fernsy"; while a recording runs, the menu warns
that quitting stops it. It can be turned off in Settings.

#### Scenario: Recording in progress
- **WHEN** a recording runs
- **THEN** the menu bar symbol shows a red dot and the menu offers "Stop Recording" and warns that quitting stops it
