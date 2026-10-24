## ADDED Requirements

### Requirement: Recordings keep trying while the channel delivers nothing
A recording whose channel delivers no data, or is reported offline by the provider, SHALL
keep trying until its recording window (including padding) ends and start writing as soon
as data arrives. A running recording whose channel drops out SHALL continue in the same file
when the channel returns. Only a recording without any data by the end of its window SHALL
be marked failed with "no data from the channel".

#### Scenario: Channel silent at the start
- **WHEN** a recording is scheduled from 20:05 to 21:55 and the channel delivers nothing until 20:12
- **THEN** the recording starts writing at 20:12 and ends at 21:55 as recorded

#### Scenario: Channel offline at the start
- **WHEN** the provider reports the channel offline at 20:05 and it comes back at 20:30
- **THEN** the recording contains the show from 20:30 on, without the user doing anything

#### Scenario: Outage during the show
- **WHEN** the channel goes offline at 21:00 during a recording and returns at 21:10
- **THEN** the same file continues from 21:10 and the recording ends at its planned end as recorded

#### Scenario: No data for the whole window
- **WHEN** the channel delivers nothing from the start until the end of the recording window
- **THEN** the recording is marked failed with "Keine Daten vom Sender"

#### Scenario: Player alone
- **WHEN** no recording uses a channel and the provider reports it offline
- **THEN** the player gives up and shows the offline message as before

### Requirement: Waiting recordings are shown as running
While a recording waits for its channel's first data, the Recordings section SHALL list it as
running with the note that it is waiting for the channel, and it can be stopped like a
running recording.

#### Scenario: Waiting is visible
- **WHEN** a recording's start time has passed and no data has arrived yet
- **THEN** the Recordings section lists it as running with "Wartet auf den Sender …"

#### Scenario: Stopping a waiting recording
- **WHEN** the user stops a recording that is still waiting for data
- **THEN** it is listed as failed with "Keine Daten vom Sender" and no file is kept
