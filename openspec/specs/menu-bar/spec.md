# menu-bar Specification

## Purpose
Keeps Fernsy reachable and visibly running when its windows are closed, so scheduled
recordings are not lost by accident.

## Requirements

### Requirement: Menu bar item
The app SHALL show a menu bar item (TV symbol, with a red dot while recording) listing
running recordings with their end time and a stop action, the next scheduled recording,
"Open Fernsy", "Show Recordings" and "Quit Fernsy"; while a recording runs, the menu warns
that quitting stops it. It can be turned off in Settings.

#### Scenario: Recording in progress
- **WHEN** a recording runs
- **THEN** the menu bar symbol shows a red dot and the menu offers "Stop Recording" and warns that quitting stops it

### Requirement: Running without windows
Closing the last window SHALL NOT quit the app. With the menu bar item enabled the Dock icon
SHALL disappear while no window is open and return when one opens.

#### Scenario: Closing all windows
- **WHEN** the user closes every Fernsy window
- **THEN** Fernsy keeps running in the menu bar without a Dock icon

#### Scenario: Reopening
- **WHEN** the user chooses "Open Fernsy" in the menu bar
- **THEN** the library window opens and the Dock icon is back

### Requirement: Open at login
Settings › Aufnahmen SHALL offer "Beim Anmelden öffnen", off by default. It SHALL register or
remove Fernsy as a macOS login item and SHALL show the state macOS reports, including a hint
with a button to the Login Items settings when macOS asks for approval. Opened at login,
Fernsy SHALL start without a window (in the menu bar if its item is on) and run scheduled
recordings. Debug builds SHALL NOT register a login item.

#### Scenario: Turning it on
- **WHEN** the user turns on "Beim Anmelden öffnen"
- **THEN** Fernsy appears under System Settings › General › Login Items and opens at the next login

#### Scenario: Removed in System Settings
- **WHEN** the user removes Fernsy from the login items in System Settings
- **THEN** the switch in Fernsy's Settings shows it as off

#### Scenario: Login with a scheduled recording
- **WHEN** the user logs in and a recording is scheduled for later that evening
- **THEN** Fernsy runs in the menu bar without opening a window, and the recording starts on time

#### Scenario: Opened by the user
- **WHEN** the user opens Fernsy from the Dock or the Applications folder
- **THEN** the library window opens as before
