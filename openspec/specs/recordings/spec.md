# recordings Specification

## Purpose
Lets the user record live TV: plan shows from the program, record what is on now, and watch
or manage the recordings later, within the account's connection limit.

## Requirements

### Requirement: Schedule a show
The guide (detail bar and context menu) and the channel list's now/next panel SHALL offer
"Record" for running and future shows and "Remove Recording" for planned ones; planned and
recorded shows are marked in the guide.

#### Scenario: Planning from the guide
- **WHEN** the user selects tonight's 20:15 show and clicks Record
- **THEN** it appears under Recordings › Scheduled and is marked in the guide

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

### Requirement: Record the current show from the player
In live TV the record button and the R key SHALL record the show on now, including the part
before pressing as far as the buffer reaches back to its start; pressing again stops it.
Without program data it records the next two hours.

#### Scenario: Late start
- **WHEN** the user has watched a channel for 20 minutes and presses R 15 minutes into a show
- **THEN** the recording contains the show from its beginning

### Requirement: Recordings run while the app runs
Recordings SHALL run while Fernsy is open, also with all windows closed; the Mac SHALL be kept
from idle sleep during a recording and within the hour before one. Recordings whose time
passed while the app was not running are marked missed.

#### Scenario: Window closed
- **WHEN** all Fernsy windows are closed before a scheduled recording
- **THEN** the recording still happens

#### Scenario: App not running
- **WHEN** Fernsy was quit during a scheduled show
- **THEN** that recording is listed as missed

### Requirement: Recording files
Recordings SHALL be saved as MPEG-TS files in `~/Movies/Fernsy` named
"<Channel> – <Title> (<yyyy-MM-dd HH.mm>).ts", playable in Fernsy and other players, also
while still recording.

#### Scenario: Watching a running recording
- **WHEN** the user plays a recording that is still running
- **THEN** it plays from the start and can be watched up to the current moment

### Requirement: Recordings section
The library SHALL have a Recordings section listing running, scheduled and recorded entries
(with status, time, size, errors), with play, stop, remove, move to Trash and Show in Finder.

#### Scenario: Deleting a recording
- **WHEN** the user deletes a finished recording
- **THEN** it disappears from the list and its file is moved to the Trash

### Requirement: Shared connection
Watching and recording the same channel SHALL use one provider connection.

#### Scenario: Watching the channel being recorded
- **WHEN** a recording runs on a single-stream account and the user opens that channel
- **THEN** it plays (with timeshift) without a second connection

### Requirement: Ask before taking a connection
When a recording needs a connection the player or another recording holds, the app SHALL
ask; without an answer within one minute the recording starts. Switching the player to
another channel while a recording holds the only connection SHALL also ask first.

#### Scenario: Recording starts while another channel plays
- **WHEN** a scheduled recording on channel B starts while channel A plays on a single-stream account
- **THEN** the app asks "Switch and Record" or "Skip Recording" and switches to B after a minute without answer

#### Scenario: Zapping during a recording
- **WHEN** the user switches the player away from the recorded channel on a single-stream account
- **THEN** the app asks whether to stop the recording and switch

### Requirement: Quitting asks
Quitting with running or scheduled (next 24 h) recordings SHALL ask for confirmation; a
running recording keeps what was recorded so far.

#### Scenario: Quit during a recording
- **WHEN** the user quits while a recording runs and confirms
- **THEN** the file is kept with the content up to now and the entry shows as recorded

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
