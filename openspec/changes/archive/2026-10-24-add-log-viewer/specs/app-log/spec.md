## ADDED Requirements

### Requirement: Event log
Every build SHALL record app events with time, level (info, warning, error, detail) and
category. At least these are recorded: playback start, end and errors; network reconnects
and give-ups; tuner and timeshift problems; recording start, end and failure; catalog,
program guide and Jellyfin loads and failures; Picture in Picture start and stop.

#### Scenario: Reconnect during live TV
- **WHEN** a live stream's connection drops and is replaced
- **THEN** the log shows a network warning with the reason and the reconnect attempt

#### Scenario: Recording without data
- **WHEN** a recording ends without any data from its channel
- **THEN** the log shows a recordings error naming the show and "no data from the channel"

### Requirement: No credentials in the log
Log entries SHALL NOT contain the Xtream username or password, Jellyfin access tokens, or
the values of `password` and `api_key` URL parameters; they are replaced by "•••" before an
entry is stored.

#### Scenario: Stream URL in an error
- **WHEN** an error message contains a stream URL with the account's username and password
- **THEN** the stored entry shows the URL with "•••" in their place

### Requirement: Log kept across one restart
The log SHALL be kept in a file in the app's own Caches folder for the current and the
previous app run, each limited in size (oldest entries dropped first), and SHALL never be
sent anywhere.

#### Scenario: After a restart
- **WHEN** the user quits Fernsy, starts it again and opens the log
- **THEN** the entries of the previous run can be shown

### Requirement: Log window
The main menu SHALL offer Window › Log (⌥⌘L), opening a log window with the entries of the
current run, newest at the bottom and following new entries, filters for level and
category, a text search, a switch to the previous run, Copy (selection or all), Save as a
text file and Clear. Detail entries are hidden unless the level filter includes them.

#### Scenario: Filtering
- **WHEN** the user selects the category Recordings and the level Errors
- **THEN** only recording errors are listed

#### Scenario: Saving for support
- **WHEN** the user chooses Save and picks a location
- **THEN** a text file with the listed entries (time, level, category, message) is written there
