## MODIFIED Requirements

### Requirement: Channel list with now and next
The Live TV section SHALL show the selected category's channels as rows with number, logo,
tagged name, current show with progress, next show and status marks. Selecting a channel SHALL
show a detail pane (below the list in a narrow window) with "Play", the favourite toggle, the
current show with remaining time and "Record", and the following shows, each with "Record" or
"Scheduled". Rows and pane SHALL follow the clock, showing a new show within a minute of its
start.

#### Scenario: Selecting a channel
- **WHEN** the user selects a channel in the list
- **THEN** the pane on the right shows what is on now with its progress and remaining time, and what follows

#### Scenario: Recording mark in the row
- **WHEN** a channel is being recorded
- **THEN** its row shows "REC" with a red dot and its progress bar is red

#### Scenario: Recording a later show from the pane
- **WHEN** the user clicks "Record" next to the 23:30 show in the pane
- **THEN** the show is scheduled and its button reads "Scheduled"

#### Scenario: Show changes while the list is open
- **WHEN** the list has been open since 22:10, a show ends at 22:30 and the next begins
- **THEN** by 22:31 the row and the pane show the new show as current, with its progress, and the one after it as next

#### Scenario: Programme runs out while visible
- **WHEN** a row stays visible until its channel's programme is no longer fresh
- **THEN** the programme is fetched again without the user leaving the list
