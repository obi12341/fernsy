# Spec Delta

## ADDED Requirements

### Requirement: Server offered wherever the Mac records a show
With a paired Fernsy Server, every place on the Mac that offers to record a show from the guide
SHALL also offer to record it on the server: the guide's detail and grid, the channel list, the
channel pane, the search results and Start. A show the server already has an unfinished order for
SHALL offer to remove it from the server there instead.

#### Scenario: From the search
- **WHEN** the user picks a later show in the Mac's search results with a paired server
- **THEN** the record question offers "Record" and "Record on Server"

#### Scenario: From a context menu
- **WHEN** the user opens the context menu of a show in the Mac's guide grid with a paired server
- **THEN** the menu has "Record on Server" below "Record"

#### Scenario: Already ordered
- **WHEN** the show was ordered on the server from the iPad and the user opens its context menu on the Mac
- **THEN** the menu offers "Remove from Server" and no second order

#### Scenario: No server
- **WHEN** no server is paired
- **THEN** none of these places mentions the server

### Requirement: One server order per show
Ordering a show on the server SHALL first take the server's current orders into account: when an
unfinished order for the same channel and start exists, from any device, no second order SHALL be
written and the existing one SHALL be shown.

#### Scenario: Ordered on two devices
- **WHEN** the user orders a show on the Apple TV and, a minute later, the same show on the Mac
- **THEN** the server has one order for it and both devices list it once

### Requirement: Server order that would start now
An order whose recording would begin at once (the show runs, or starts within its lead time)
SHALL be refused with the reason when the streams this device uses and the server's running
recordings already use all streams of the account. Nothing SHALL be written to the server and
playback on the device SHALL continue. Orders for later shows SHALL NOT be checked this way.

#### Scenario: Watching on a single-stream account
- **WHEN** the account allows one stream, the Mac plays a channel live and the user chooses "Record on Server" for a show that runs now
- **THEN** the Mac says that the account's stream is in use here, playback continues and the server gets no order

#### Scenario: Later show
- **WHEN** the same user chooses "Record on Server" for a show that starts in two hours
- **THEN** the order is written and listed as sent to the server

#### Scenario: Room for the server
- **WHEN** the account allows two streams, the Mac plays one channel and the server records nothing
- **THEN** an order for a show that runs now is written
