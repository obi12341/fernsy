## MODIFIED Requirements

### Requirement: Control service without an account
The control service SHALL store only encrypted orders, states and status that it cannot read,
SHALL need no account or subscription of its own, and SHALL limit what one user can store and how
often they can ask. A request that only reads, or finds nothing new, SHALL write nothing to the
service's database, apart from marking the user's space as used at most once a day.

#### Scenario: What the service sees
- **WHEN** the user schedules a show for the server
- **THEN** the control service stores an item it cannot read: no channel, title or time

#### Scenario: Quiet poll
- **WHEN** a paired server asks for new orders and none has changed since its last look
- **THEN** the control service answers without writing to its database

### Requirement: Server status
The server SHALL report its state (paired, last contact, free space, running and next
recordings, errors) to the apps through the control service and on a local status page, and log
without credentials, keys or stream URLs. It SHALL send its report when anything in it other than
last contact and free space changed, and otherwise at least every 5 minutes.

#### Scenario: Server offline
- **WHEN** the server has not reported for 10 minutes
- **THEN** the apps show it as offline with the time of its last contact

#### Scenario: Recording starts
- **WHEN** a recording starts on the server
- **THEN** the apps show it as running after the server's next poll, without waiting for the 5-minute report

#### Scenario: Nothing happens
- **WHEN** the server records nothing and no order changes for an hour
- **THEN** it sends about 12 reports in that hour, and the apps show it online with a last contact at most 5 minutes old
