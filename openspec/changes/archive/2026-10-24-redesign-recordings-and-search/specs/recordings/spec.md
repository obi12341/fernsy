## MODIFIED Requirements

### Requirement: Recordings section
The library SHALL have a Recordings section listing running, scheduled and recorded entries
(with status, time, size, errors), with play, stop, remove, move to Trash and Show in Finder.
A recording that did not succeed SHALL say so in its row with a symbol, the outcome
("fehlgeschlagen", "verpasst", "ausgelassen") and its cause; a permanent note at the bottom
SHALL say that recordings only run while Fernsy is open.

#### Scenario: Deleting a recording
- **WHEN** the user deletes a finished recording
- **THEN** it disappears from the list and its file is moved to the Trash

#### Scenario: Failed recording
- **WHEN** a recording failed because the channel delivered no data
- **THEN** its row shows a warning symbol with "fehlgeschlagen · Keine Daten vom Sender"

### Requirement: Recordings list shows the recording window
Each scheduled, running or finished recording in the Recordings section SHALL show the show's
time and, when padding applies, the actual recording window including the padding, side by
side on one line.

#### Scenario: Scheduled recording with padding
- **WHEN** a show from 20:15 to 21:45 is scheduled with 10/10 minutes padding
- **THEN** the list shows "20:15 – 21:45" and the recording window "20:05 – 21:55"
