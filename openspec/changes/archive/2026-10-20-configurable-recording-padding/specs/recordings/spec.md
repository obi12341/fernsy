## MODIFIED Requirements

### Requirement: Padding
Recordings planned from program data SHALL start before and end after the show's scheduled
time by the configured padding. Both paddings SHALL be settable in Settings to any whole
number of minutes from 0 to 60; the default is 10 minutes before and 10 minutes after.

#### Scenario: Default padding
- **WHEN** a show from 20:15 to 21:45 is recorded with default settings
- **THEN** the file covers 20:05 to 21:55

#### Scenario: Custom padding
- **WHEN** the user sets 3 minutes before and 25 minutes after and records a show from 20:15 to 21:45
- **THEN** the file covers 20:12 to 22:10

#### Scenario: Out-of-range input
- **WHEN** the user enters 90 minutes or a negative value
- **THEN** the value is limited to 60 or 0 minutes

#### Scenario: Previously chosen values
- **WHEN** a user had explicitly chosen 5 minutes before in an earlier version
- **THEN** 5 minutes is kept; only users who never changed it get the new default

## ADDED Requirements

### Requirement: Padding changes apply to scheduled recordings
Changing a padding in Settings SHALL update every scheduled recording that was planned from
program data and has not started yet; running and finished recordings keep their window.

#### Scenario: Changing the padding after planning
- **WHEN** a show is scheduled with 10 minutes before and the user then sets 15 minutes before
- **THEN** the scheduled recording starts 15 minutes before the show

#### Scenario: Recording already running
- **WHEN** the padding is changed while a recording runs
- **THEN** that recording keeps its original start and end

### Requirement: Recordings list shows the recording window
Each scheduled, running or finished recording in the Recordings section SHALL show the show's
time and, when padding applies, the actual recording window including the padding.

#### Scenario: Scheduled recording with padding
- **WHEN** a show from 20:15 to 21:45 is scheduled with 10/10 minutes padding
- **THEN** the list shows "20:15 – 21:45" and the recording window "20:05 – 21:55"
