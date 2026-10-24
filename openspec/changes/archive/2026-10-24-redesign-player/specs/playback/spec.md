## ADDED Requirements

### Requirement: Player overlay
The player's controls SHALL appear as one glass panel at the bottom, with a caption at the
top left (channel logo, name, tags and current show; for films title and details) and,
while the channel is recorded, a red "Aufnahme · bis HH:MM" mark at the top right. The
panel holds the timeline, play/pause with ±10 s (films also ±60 s), volume, one menu for
audio and subtitle tracks, technical info, Picture in Picture and full screen. The overlay
follows the system appearance.

#### Scenario: Recording while watching
- **WHEN** the channel being watched is recorded until 22:55
- **THEN** the top right shows "Aufnahme · bis 22:55" and the record button reads "Aufnahme beenden"

#### Scenario: Seeking in a film by the mouse
- **WHEN** the pointer hovers over the film's timeline
- **THEN** a mark shows the time at the pointer before clicking

### Requirement: Player status cards
While a stream loads, the player SHALL show the channel's logo with a spinner and
"<name> wird geladen …"; while the connection is restored it SHALL say so (with the attempt
number when the player restarts the stream); when a channel is offline at the provider it
SHALL explain that the provider, not the user's connection, is the cause and offer "Erneut
versuchen" and, for live channels, "Nächster Sender".

#### Scenario: Offline channel
- **WHEN** a channel turns out to be offline at the provider
- **THEN** a card says so and offers "Erneut versuchen" and "Nächster Sender ↓"
