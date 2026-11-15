## MODIFIED Requirements

### Requirement: Program guide on iPhone and iPad
Programm SHALL show a guide grid for the chosen source that scrolls in both directions by touch:
channels with logo and name stay at the left edge, shows on a time axis with the time now marked,
past shows dimmed and running ones highlighted. Tapping a running show SHALL play its channel;
tapping a later show SHALL show its details. Rows without listings, still loading, or with gaps
SHALL show bars there that play the channel when tapped. It SHALL scroll without stalls at any
size. A long press on any show SHALL open a menu with what can be done with it: watch the
channel (running show) or play it from its start (past show of an archive channel), record it
on the paired Fernsy Server or cancel the server's order for it (running and later shows, with a
paired server only), and show its details. An order for a show that runs now SHALL follow the
rule for server orders that would start now: refused with its reason while this device uses all
of the account's streams, with playback going on.

#### Scenario: Playing from the guide
- **WHEN** the user taps a show that is running now
- **THEN** its channel plays full screen

#### Scenario: Recording a running show on the server
- **WHEN** a Fernsy Server is paired, nothing plays on the iPhone, and the user long-presses a show that began ten minutes ago and chooses "Record on Fernsy Server"
- **THEN** the server gets an order for the show and the guide marks the show as recorded by the server

#### Scenario: Cancelling from the menu
- **WHEN** the server has an order for a running show and the user long-presses it
- **THEN** the menu offers "Cancel Recording" instead of "Record on Fernsy Server", and choosing it removes the order and the mark

#### Scenario: Watching the channel on a single-stream account
- **WHEN** the account allows one stream, the iPhone plays the channel in Picture in Picture, and the user orders the running show on the server from the menu
- **THEN** the iPhone says that the account's stream is in use here, playback goes on and the server gets no order

#### Scenario: Without a server
- **WHEN** no Fernsy Server is paired and the user long-presses a running show
- **THEN** the menu offers watching the channel and the details, and nothing about recording

#### Scenario: Later show
- **WHEN** the user long-presses a show that starts tonight
- **THEN** the menu offers recording on the server and the details, as its sheet does

#### Scenario: Channel without listings
- **WHEN** the provider sends no listings for a channel
- **THEN** its row shows the bar "Keine Programmdaten", and tapping it plays the channel

#### Scenario: Scrolling a large guide
- **WHEN** the source has hundreds of channels, some with a week of archive, and the user scrolls
  the guide up, down and back in time on an iPad
- **THEN** the grid follows the finger, the app stays responsive, and only the rows that came on
  screen request their listings
