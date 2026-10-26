## Purpose
Fernsy on Apple TV: what the Apple TV app does, how it shares the Mac app's provider, guide
and playback behavior, what tvOS limits, and how its development builds stay apart from
real accounts.

## ADDED Requirements

### Requirement: Apple TV app
Fernsy SHALL have an app for Apple TV 4K (tvOS 27) that signs in to an Xtream account, lists
its live channels with the current show, and plays a live channel full screen with pause,
back 10 s and back to live. It SHALL use the same provider, guide and playback behavior as the
Mac app, including channel-name cleanup, seamless reconnects, slow-delivery handling and the
timeshift buffer, and be operated with the Siri Remote alone.

#### Scenario: Watching a live channel
- **WHEN** the user selects a channel in the list with the Siri Remote
- **THEN** it plays full screen, and the remote pauses it, goes back 10 s and returns to live

#### Scenario: Slow delivery on Apple TV
- **WHEN** a live connection delivers about a fifth of the needed rate while watching on Apple TV
- **THEN** it is replaced via the provider's load balancer as in the Mac app

#### Scenario: Back from the player
- **WHEN** the user presses Back in the player
- **THEN** playback stops and the channel list shows again with the same channel focused

### Requirement: Storage on Apple TV
The Apple TV app SHALL keep the timeshift buffer and caches only where tvOS may delete them,
and SHALL work when they are gone. It SHALL NOT record: tvOS has no lasting local storage for
recordings.

#### Scenario: Caches cleared
- **WHEN** tvOS removed the app's caches while it was not running
- **THEN** the app loads the channel list again and plays as usual

### Requirement: Development builds of the Apple TV app
Debug builds of the Apple TV app SHALL use their own bundle id and name, start muted, refuse
to stream from servers other than the demo server unless explicitly allowed, and offer a debug
MCP server on their own port for playing, seeking, playback state, a snapshot and the log. A
script SHALL build the app, start the tvOS simulator with its window and launch the app with
debug settings.

#### Scenario: Running the app on this Mac
- **WHEN** the developer runs the script with the demo account
- **THEN** the simulator window shows the app with the demo channels, without sound

#### Scenario: Real provider in a debug build
- **WHEN** a debug build of the Apple TV app is about to stream from a server that is not the demo server
- **THEN** it refuses and says so, and no stream request reaches that server
