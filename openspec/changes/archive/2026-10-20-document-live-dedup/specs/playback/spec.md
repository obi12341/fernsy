## MODIFIED Requirements

### Requirement: Seamless live reconnect
A dropped or stalled live connection SHALL be replaced in place without a visible restart:
replayed content is dropped, timelines of different backends are lined up, and playback
continues where it was. A full restart is tried up to 8 times before an error is shown.

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

#### Scenario: Several quick reconnects
- **WHEN** a provider accepts and drops connections several times within seconds
- **THEN** packets still arriving from older connections are placed with their own connection's offset, and the source gives up after 8 attempts in one incident
