## ADDED Requirements

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
