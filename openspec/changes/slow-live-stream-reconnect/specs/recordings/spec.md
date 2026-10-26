## MODIFIED Requirements

### Requirement: Recordings section
The library SHALL have a Recordings section listing running, scheduled and recorded entries
(with status, time, size, errors), with play, stop, remove, move to Trash and Show in Finder.
A recording that did not succeed SHALL say so in its row with a symbol, the outcome
("fehlgeschlagen", "verpasst", "ausgelassen") and its cause; a permanent note at the bottom
SHALL say that recordings only run while Fernsy is open. A recording that misses content
because the provider delivered too little or nothing for 10 s or more SHALL stay recorded and
show each such gap with its clock time and length, naming the provider's delivery as the
cause; this already shows while the recording runs.

#### Scenario: Deleting a recording
- **WHEN** the user deletes a finished recording
- **THEN** it disappears from the list and its file is moved to the Trash

#### Scenario: Failed recording
- **WHEN** a recording failed because the channel delivered no data
- **THEN** its row shows a warning symbol with "fehlgeschlagen · Keine Daten vom Sender"

#### Scenario: Gap in a recording
- **WHEN** the provider delivered too little from 21:38 to 21:40 during a recording, and about 1:41 of the show is missing
- **THEN** the recording is listed as recorded, and its row shows a note symbol with "Lücke 21:38 (1:41) – Anbieter hat zu wenig geliefert"

#### Scenario: Short hiccup
- **WHEN** a reconnect during a recording loses less than 10 s of content
- **THEN** no gap is shown
