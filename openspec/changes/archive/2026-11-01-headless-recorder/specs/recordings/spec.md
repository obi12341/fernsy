## ADDED Requirements

### Requirement: Recording on a Fernsy Server
With a paired Fernsy Server, scheduling a show in any app SHALL offer the server as where it
records, as the default where the device itself does not record (iPhone, iPad). The recordings
lists SHALL show the server's orders with their state, and cancelling one SHALL cancel it on the
server.

#### Scenario: Schedule on the iPad
- **WHEN** the user schedules a show on the iPad with a paired server
- **THEN** the show is scheduled on the server and listed as such on every device

#### Scenario: Cancel on the Mac
- **WHEN** the user cancels a server recording in the Mac's list
- **THEN** the server drops it and every device stops listing it
