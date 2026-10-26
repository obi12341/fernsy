## MODIFIED Requirements

### Requirement: Seamless live reconnect
A dropped, stalled or too slow live connection SHALL be replaced in place without a visible
restart: replayed content is dropped, timelines of different backends are lined up, and
playback continues where it was. A connection is too slow when, over the last 15 s, it
delivered less than 9 s of content; this is judged on the content received, independent of
whether and where someone watches. A reconnect caused by slow delivery, or by a stall within
60 s after slow delivery, SHALL skip the current edge host. When the connection after such a
switch is slow again within 2 minutes, switching servers did not help: the source SHALL then
judge over a longer window (30 s, then 60 s, each needing 60 % of it) before it switches again,
and return to 15 s after 5 minutes without slow delivery. A full restart is tried up to 8
times before an error is shown.

#### Scenario: Connection drops
- **WHEN** the provider closes a live connection while 6 s are buffered
- **THEN** playback continues without a jump or repeated scenes and the info overlay counts a seamless reconnect

#### Scenario: New connection replays the server's buffer
- **WHEN** the new connection starts with several seconds the player already played
- **THEN** those packets are dropped and counted as duplicates in the info overlay

#### Scenario: New connection lands on a backend with another clock
- **WHEN** the reconnect is answered by a backend whose timestamps differ by minutes for the same content
- **THEN** the offset is measured from identical packets and playback continues without a jump

#### Scenario: Real gap in the content
- **WHEN** the new connection continues later than where playback was (content was missed)
- **THEN** gaps under 10 s are closed on the timeline, video resumes at the next keyframe, and larger jumps resynchronize playback

#### Scenario: Stalled connection
- **WHEN** no data arrives for 4 s while the player has less than 4 s left (or for 30 s regardless)
- **THEN** the connection is replaced, first via the same edge host, then via the provider's load balancer

#### Scenario: Player has run dry
- **WHEN** a player reports less than 1 s left and no data has arrived for 2 s
- **THEN** the connection is replaced without waiting for the 4 s rule

#### Scenario: Burst delivery with buffer left
- **WHEN** a channel pauses for 3 s between bursts while the player still has 5 s left
- **THEN** the connection is kept

#### Scenario: Trickling connection
- **WHEN** a live connection keeps delivering, but only about a fifth of the data rate the channel needs
- **THEN** within 20 s of the slowdown the connection is replaced via the provider's load balancer, and the log gives slow delivery as the reason

#### Scenario: Slow delivery while only recording
- **WHEN** a channel is recorded without being watched, or watched far behind live, and its connection trickles
- **THEN** the connection is replaced the same way as while watching live

#### Scenario: Segmented delivery is not slow
- **WHEN** a channel delivers in bursts of up to 6 s of content, on average in real time
- **THEN** the connection is kept

#### Scenario: Switching servers does not help
- **WHEN** every connection trickles, because the user's own line is slow or the provider has no faster server
- **THEN** after the first switch the source judges over 30 s and then 60 s, and switches about once a minute instead of every 20 s

#### Scenario: Stall after slow delivery
- **WHEN** a connection that was slow in the last 60 s goes silent and is replaced
- **THEN** the first attempt goes to the load balancer instead of the same edge host

#### Scenario: Edge token expired
- **WHEN** the reconnect to the same edge host is answered with HTTP 403 or 401
- **THEN** the next attempt goes to the load balancer at once, without the backoff delay

#### Scenario: Edge fails again right after a reconnect
- **WHEN** the connection to an edge host stalls again within 20 s after a reconnect to that host
- **THEN** the new incident's first attempt goes to the load balancer instead of that edge

#### Scenario: Several quick reconnects
- **WHEN** a provider accepts and drops connections several times within seconds
- **THEN** packets still arriving from older connections are placed with their own connection's offset, and the source gives up after 8 attempts in one incident

#### Scenario: Server of every connection in the log
- **WHEN** a live channel's first connection or a reconnect is answered
- **THEN** the log names the server host that answered

#### Scenario: Delivery figures in the log
- **WHEN** a live connection that ran for 20 s or more ends or is replaced
- **THEN** the log, also in release builds, gives how long it ran, its lowest 15 s window of content and its longest pause between data

### Requirement: Player status cards
While a stream loads, the player SHALL show the channel's logo with a spinner and
"<name> wird geladen …"; while the connection is restored it SHALL say so (with the attempt
number when the player restarts the stream); when a channel is offline at the provider it
SHALL explain that the provider, not the user's connection, is the cause and offer "Erneut
versuchen" and, for live channels, "Nächster Sender". When live playback stalls while the
channel's connection is slow, silent or being replaced, the player SHALL say that the channel
arrives too slowly from the provider and what Fernsy does about it, instead of a bare
spinner; when macOS reports no network connection, it SHALL say that instead and not name the
provider. When a reconnect to another provider server ends such a stall, a short note SHALL
say so.

#### Scenario: Offline channel
- **WHEN** a channel turns out to be offline at the provider
- **THEN** a card says so and offers "Erneut versuchen" and "Nächster Sender ↓"

#### Scenario: Provider delivers too slowly
- **WHEN** live playback stalls while the channel's connection delivers less content than real time
- **THEN** a card reads "Der Sender kommt zu langsam vom Anbieter" with "Fernsy wechselt zu einem anderen Server des Anbieters …" while it reconnects

#### Scenario: No internet connection
- **WHEN** live playback stalls and macOS reports no network connection
- **THEN** the card reads "Keine Internetverbindung" and does not mention the provider

#### Scenario: Short stall with a healthy connection
- **WHEN** live playback stalls for a moment while the connection delivers in real time
- **THEN** only the spinner is shown, without blaming the provider

#### Scenario: Another server helps
- **WHEN** a reconnect to another provider server ends a stall caused by slow delivery
- **THEN** a note "Ein anderer Server des Anbieters liefert wieder flüssig." appears for a few seconds
