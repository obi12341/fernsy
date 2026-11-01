## MODIFIED Requirements

### Requirement: Quota
A subscription SHALL include 100 GB of cloud storage. An upload SHALL be refused before it starts
when the recording does not fit into the free storage of the subscription, with a message naming
the needed and the free space. An account that stores more than its quota SHALL keep playing,
downloading and deleting its recordings; only new uploads are refused until it is below the quota.

#### Scenario: Cloud full
- **WHEN** a 3 GB recording is uploaded with 1 GB free
- **THEN** the upload does not start and the message names 3 GB needed and 1 GB free

#### Scenario: Above the quota after a change
- **WHEN** an account stores 120 GB and the quota is 100 GB
- **THEN** its recordings play and can be deleted, and an upload is refused naming 0 GB free

#### Scenario: Storage shown
- **WHEN** a subscriber opens Settings › Fernsy Cloud
- **THEN** the storage reads as used of 100 GB
