## ADDED Requirements

### Requirement: Player status on Apple TV
The Apple TV player SHALL show its state in the middle of the screen: while an item loads, a
spinner and "<title> wird geladen …", for a live channel with its logo; while it buffers, a spinner;
while the connection is restored, "Verbindung wird wiederhergestellt …" with the attempt number
when the stream restarts. These SHALL disappear with the first picture and SHALL NOT take focus.

#### Scenario: Switching channels
- **WHEN** the user picks another channel in the channel strip
- **THEN** the channel's logo, a spinner and "<name> wird geladen …" show in the middle until its picture appears

#### Scenario: Buffering a film
- **WHEN** a film's playback runs out of data and waits for more
- **THEN** a spinner shows in the middle until playback continues

#### Scenario: Stream restarted
- **WHEN** the player restarts a live stream after its connection broke
- **THEN** "Verbindung wird wiederhergestellt …" shows with "Versuch 1 von 8"

### Requirement: Stall cause on Apple TV
When live playback stalls for over a second while the channel's connection is slow, silent or
being replaced, the Apple TV player SHALL say that the channel arrives too slowly from the
provider and what Fernsy does about it; without a network connection it SHALL say that instead
and not name the provider. A short stall on a healthy connection SHALL show only the spinner.
When another provider server ends such a stall, a note SHALL say so for a few seconds.

#### Scenario: Provider delivers too slowly
- **WHEN** live playback stalls while the channel delivers less content than real time
- **THEN** a card reads "Der Sender kommt zu langsam vom Anbieter" with what Fernsy does about it

#### Scenario: No network
- **WHEN** live playback stalls and the Apple TV has no network connection
- **THEN** the card reads "Keine Internetverbindung" and does not mention the provider

### Requirement: Playback failure on Apple TV
When a stream fails, the Apple TV player SHALL show a card with the reason; for a channel
offline at the provider it SHALL explain that the provider, not the user's connection, is the
cause. The card SHALL offer "Erneut versuchen" and, for live channels, "Nächster Sender", both
reachable with the remote; Back SHALL still close the player.

#### Scenario: Offline channel
- **WHEN** a live channel turns out to be offline at the provider
- **THEN** a card says so and offers "Erneut versuchen" and "Nächster Sender", and choosing "Nächster Sender" tunes the next channel of the list

#### Scenario: Trying again
- **WHEN** the user chooses "Erneut versuchen" on a failed film
- **THEN** the film loads again, with the spinner and "<title> wird geladen …" while it loads

### Requirement: Preview loading on Apple TV
While Live TV's preview pane loads the focused channel, it SHALL show a spinner over the pane
until the channel's picture appears.

#### Scenario: Previewing another channel
- **WHEN** focus rests on another channel row and its preview starts
- **THEN** a spinner shows in the pane until the channel's picture appears
