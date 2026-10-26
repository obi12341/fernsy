## ADDED Requirements

### Requirement: Development builds have their own identity
Debug builds SHALL use their own bundle id (`de.mobilistics.fernsy.dev`), display name
"Fernsy Dev" and a marked app icon, so they have their own settings, accounts, recordings
list, caches, keychain scope and system registrations, and SHALL write recordings to
`~/Movies/Fernsy Dev`. Release, App Store and DMG builds are unchanged.

#### Scenario: Debug build next to the installed app
- **WHEN** the installed Fernsy is recording and a debug build starts without any environment
- **THEN** the debug build shows the sign-in screen, sees none of the installed app's accounts, settings or recordings, and the recording continues

#### Scenario: Settings stay apart
- **WHEN** the debug build changes a setting
- **THEN** the installed app's settings are unchanged

#### Scenario: Release unchanged
- **WHEN** a Release, App Store or DMG build is made
- **THEN** it keeps the bundle id `de.mobilistics.fernsy`, the name "Fernsy" and the normal icon

### Requirement: Development builds stay quiet
Debug builds SHALL start muted unless sound is requested, SHALL NOT store the volume, and
SHALL NOT bring themselves to the front unless requested.

#### Scenario: Quiet test run
- **WHEN** a debug build plays the demo stream and opens its player while the user watches full screen in the installed app
- **THEN** no sound plays, and the user's app stays in front and keeps the keyboard focus

### Requirement: Development builds stream only from the demo server
Debug builds SHALL refuse to stream from servers other than the demo server unless
explicitly allowed, so a test never takes the user's single stream by accident.

#### Scenario: Real provider refused
- **WHEN** a debug build is started with a server other than the demo server and without the explicit allowance
- **THEN** it refuses to play live channels, films or recordings from it and says why

### Requirement: Production data reaches development builds only as a copy
Data from the installed app SHALL reach a debug build only through an explicit copy into
the debug build's container, which reads the installed app's data without changing it,
leaves out keychain items, and turns scheduled or running recordings into skipped ones.

#### Scenario: Copied data for a test
- **WHEN** the developer copies the installed app's data into the dev container
- **THEN** the debug build shows the copied account's channels, guide and recordings list, no keychain item is copied, and copied scheduled recordings are listed as skipped
