# Spec Delta

## ADDED Requirements

### Requirement: Upload throughput
While one recording uploads, the Mac SHALL send several of its parts at the same time, so that
a single upload can use most of the user's upstream bandwidth instead of waiting for each part
before sending the next. At most four parts SHALL be in flight at once. Parts that finished
SHALL count as uploaded even when earlier parts are still missing, and resuming SHALL upload
only the parts that are missing.

#### Scenario: Several parts in flight
- **WHEN** a 3 GB recording uploads
- **THEN** up to four of its parts are sent at the same time, never more

#### Scenario: Resume after parts finished out of order
- **WHEN** an upload is interrupted after parts 1, 2 and 4 finished but part 3 did not
- **THEN** after Fernsy runs again only part 3 and the parts after 4 are uploaded, and the recording in the cloud plays from start to end

#### Scenario: Cancel while parts are in flight
- **WHEN** the user cancels an upload while several parts are being sent
- **THEN** the sending stops, nothing of it stays in the cloud and the recording shows no cloud state
