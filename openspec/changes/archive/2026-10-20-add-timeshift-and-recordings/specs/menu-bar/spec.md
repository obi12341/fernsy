## Purpose

Keeps Fernsy reachable and visibly running when its windows are closed, so scheduled
recordings are not lost by accident.

## ADDED Requirements

### Requirement: Menu bar item
The app SHALL show a menu bar item (TV symbol, red record symbol while recording) listing
running recordings with their end time and a stop action, the next scheduled recording,
"Open Fernsy", "Show Recordings" and "Quit Fernsy". It can be turned off in Settings.

#### Scenario: Recording in progress
- **WHEN** a recording runs
- **THEN** the menu bar symbol is the red record symbol and the menu offers "Stop Recording"

### Requirement: Running without windows
Closing the last window SHALL NOT quit the app. With the menu bar item enabled the Dock icon
SHALL disappear while no window is open and return when one opens.

#### Scenario: Closing all windows
- **WHEN** the user closes every Fernsy window
- **THEN** Fernsy keeps running in the menu bar without a Dock icon

#### Scenario: Reopening
- **WHEN** the user chooses "Open Fernsy" in the menu bar
- **THEN** the library window opens and the Dock icon is back
