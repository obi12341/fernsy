## ADDED Requirements

### Requirement: Real overlaps are refused within the stream limit
Planning a recording (guide, detail pane, context menu, player record button and R key) SHALL
be refused when the shows' own times without padding would need more streams at once than the
account allows. Recordings on the same channel count as one stream. The refusal SHALL name the
recordings in the way and the account's limit; nothing is planned.

#### Scenario: Overlapping shows on a single-stream account
- **WHEN** "Tatort" on channel 1 from 20:15 to 21:45 is planned and the user records a show on channel 2 from 21:00 to 22:00 on a single-stream account
- **THEN** Fernsy refuses with a message naming "Tatort" and the limit of 1 stream, and nothing is added

#### Scenario: Enough streams
- **WHEN** the same two shows are planned on an account allowing 2 streams
- **THEN** both are planned

#### Scenario: Same channel
- **WHEN** two overlapping shows on the same channel are planned on a single-stream account
- **THEN** both are planned

### Requirement: Padding gives way to other recordings
When padding would need more streams than the account allows, it SHALL be shortened so the
recordings fit, never reaching into another recording's show time; the earlier show's
after-padding takes precedence over the later show's before-padding. Planning SHALL say by how
much. The shortening SHALL be recalculated when recordings, padding settings or the limit
change. Padding overlaps on the same channel stay.

#### Scenario: Back to back on different channels
- **WHEN** show A on channel 1 ends at 21:45 and show B on channel 2 starts at 21:45, with 10/10 minutes padding on a single-stream account
- **THEN** A records until 21:45 and B from 21:45, and planning B says the padding is shortened

#### Scenario: Enough streams for the padding
- **WHEN** the same back-to-back shows are planned on an account allowing 2 streams
- **THEN** A records until 21:55 and B from 21:35, without a notice

#### Scenario: Third channel on a two-stream account
- **WHEN** on an account allowing 2 streams, A on channel 1 ends at 21:45, B on channel 2 starts at 21:45 and C on channel 3 starts at 21:50, all with 10/10 minutes padding
- **THEN** A records until 21:50, B from 21:35 and C from 21:50, because A's after-padding comes before C's before-padding and no padding reaches into C's show

#### Scenario: Gap between the shows
- **WHEN** show A ends at 21:45 and show B on another channel starts at 21:51, with 10/10 minutes padding on a single-stream account
- **THEN** A records until 21:51 and B from 21:51

#### Scenario: Neighbour removed
- **WHEN** the user removes recording B after its neighbour A was shortened
- **THEN** A gets its full padding again

#### Scenario: Same channel back to back
- **WHEN** show A and show B follow each other on the same channel with 10/10 minutes padding
- **THEN** A records until 21:55 and B from 21:35, without a notice

### Requirement: Handover between back-to-back recordings
When one recording's window ends where the next recording's window on another channel begins,
the next recording SHALL take over the connection as soon as the first releases it, without
asking and without tuning in early.

#### Scenario: Handover on a single-stream account
- **WHEN** recording A on channel 1 ends at 21:45 and recording B on channel 2 starts at 21:45 on a single-stream account
- **THEN** A ends complete, B starts right after it, and no prompt appears

## MODIFIED Requirements

### Requirement: Recordings list shows the recording window
Each scheduled, running or finished recording in the Recordings section SHALL show the show's
time and, when padding applies, the actual recording window including the padding, side by
side on one line. A window shortened for another recording SHALL show the shortened times.

#### Scenario: Scheduled recording with padding
- **WHEN** a show from 20:15 to 21:45 is scheduled with 10/10 minutes padding
- **THEN** the list shows "20:15 – 21:45" and the recording window "20:05 – 21:55"

#### Scenario: Shortened window
- **WHEN** that show is followed at 21:45 by a recording on another channel on a single-stream account
- **THEN** the list shows the recording window "20:05 – 21:45"
