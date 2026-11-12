# Spec Delta

## ADDED Requirements

### Requirement: Record Show on a Fernsy Server
The "Record Show" action SHALL have an "On Fernsy Server" switch, off by default. With it on, the
show SHALL be ordered on the paired server with the rules of ordering in the app, and the action
SHALL answer that the server records it, or why not. "Record Current Show" SHALL keep recording
on the Mac.

#### Scenario: Shortcut for the server
- **WHEN** the user runs "Record Show" for tonight's show with "On Fernsy Server" on and a server is paired
- **THEN** the show is listed under the server's orders and the action says that Fernsy Server records it

#### Scenario: Switch off
- **WHEN** the user runs "Record Show" without touching the switch
- **THEN** the Mac schedules the show itself, as before

#### Scenario: No server paired
- **WHEN** the user runs "Record Show" with "On Fernsy Server" on and no server is paired
- **THEN** nothing is scheduled and the action says that no Fernsy Server is paired
