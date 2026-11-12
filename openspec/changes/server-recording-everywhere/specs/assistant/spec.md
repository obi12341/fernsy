# Spec Delta

## MODIFIED Requirements

### Requirement: Assistant in every app
With an active Fernsy Cloud subscription, the Mac, iPhone/iPad and Apple TV apps SHALL offer an
assistant that takes a request in the user's words, answers briefly in the app's language and
acts on Fernsy: play a channel, film, episode or recording, open a page, search the guide and
the library, and schedule or cancel a recording on a device that records or, from every device,
on a paired Fernsy Server.

#### Scenario: Play by request
- **WHEN** the user asks "spiel ZDF"
- **THEN** ZDF plays, and the answer names the channel and what is on

#### Scenario: Schedule by request
- **WHEN** the user asks on the Mac to record tonight's Tatort
- **THEN** the show is scheduled, and the answer names channel, start time and that it is recorded

#### Scenario: Question without action
- **WHEN** the user asks "was läuft heute Abend im Ersten?"
- **THEN** the answer lists tonight's shows on Das Erste and nothing starts playing

#### Scenario: Schedule on the iPad with a server
- **WHEN** the user asks on the iPad, with a paired server, to record tonight's Tatort
- **THEN** the show is ordered on the server, and the answer names channel, start time and that the server records it

#### Scenario: Schedule on the server from the Mac
- **WHEN** the user asks on the Mac to record tonight's Tatort on the server
- **THEN** the show is ordered on the server and the Mac schedules nothing itself

#### Scenario: iPad without a server
- **WHEN** the user asks on the iPad, without a paired server, to record a show
- **THEN** nothing is scheduled and the answer says that the Mac, the Apple TV or a Fernsy Server records
