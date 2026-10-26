## ADDED Requirements

### Requirement: Gaps in recordings
A recording that misses content because the provider delivered too little or nothing for 10 s
or more SHALL stay recorded and show each such gap in its row in the Recordings section, with
its clock time and length, naming the provider's delivery as the cause; this already shows
while the recording runs.

#### Scenario: Gap in a recording
- **WHEN** the provider delivered too little from 21:38 to 21:40 during a recording, and about 1:41 of the show is missing
- **THEN** the recording is listed as recorded, and its row shows a note symbol with "Lücke 21:38 (1:41) – Anbieter hat zu wenig geliefert"

#### Scenario: Short hiccup
- **WHEN** a reconnect during a recording loses less than 10 s of content
- **THEN** no gap is shown
