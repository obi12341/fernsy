## ADDED Requirements

### Requirement: Archive channels
Some demo channels SHALL carry an archive flag with a length in days, their programme SHALL reach
back that far, and the server SHALL answer `/timeshift/<user>/<pass>/<minutes>/<YYYY-MM-DD:HH-MM>/<id>.ts`
with that stretch of the channel's looped recording, starting at the requested time and ending
after the requested minutes, so archive playback can be tested without a real provider.

#### Scenario: Requesting yesterday's show
- **WHEN** the app requests 90 minutes of an archive channel from yesterday 20:15
- **THEN** the server sends 90 minutes of that channel's recording, as it would have run then

#### Scenario: Channel without archive
- **WHEN** the app requests the timeshift route for a channel without an archive flag
- **THEN** the server answers 404
