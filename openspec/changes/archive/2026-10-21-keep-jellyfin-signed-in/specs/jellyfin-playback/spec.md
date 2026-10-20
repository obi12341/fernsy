## MODIFIED Requirements

### Requirement: Report playback to the server
Fernsy SHALL report playback start, progress (about every 10 s and on pause and seek) and stop
with the position, play method and selected tracks, so watched state and resume positions update
on the server; transcodes SHALL be stopped on the server when playback ends. A report rejected
because the session ended SHALL be sent again after the session is renewed, and a stream that
stops for that reason SHALL continue at the same position.

#### Scenario: Stopping halfway
- **WHEN** the user closes the player at 55 % of a film
- **THEN** the server shows the film as partly watched at that position

#### Scenario: Watching to the end
- **WHEN** a film is watched to the end credits
- **THEN** the server marks it as played

#### Scenario: Session ended during a film
- **WHEN** the server ends Fernsy's session while a film plays and the user stops it later
- **THEN** playback continues, and the server shows the position where the user stopped
