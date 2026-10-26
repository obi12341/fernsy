## MODIFIED Requirements

### Requirement: Apple TV app
Fernsy SHALL have an app for Apple TV 4K (tvOS 27) that signs in to an Xtream account, shows
its live channels by category with now and next, a program guide and recordings, and plays a
live channel full screen with pause, skipping within the timeshift buffer, back to live and
zapping. It SHALL use the same provider, guide and playback behavior as the Mac app, including
channel-name cleanup, seamless reconnects, slow-delivery handling and the timeshift buffer,
and be operated with the Siri Remote alone.

#### Scenario: Watching a live channel
- **WHEN** the user clicks a channel in Live TV with the Siri Remote
- **THEN** it plays full screen, and the remote pauses it, skips back and forward and returns to live

#### Scenario: Slow delivery on Apple TV
- **WHEN** a live connection delivers about a fifth of the needed rate while watching on Apple TV
- **THEN** it is replaced via the provider's load balancer as in the Mac app

#### Scenario: Back from the player
- **WHEN** the user presses Back in the player
- **THEN** playback stops and the screen the channel was started from shows again with that channel focused

### Requirement: Storage on Apple TV
The Apple TV app SHALL keep the timeshift buffer, caches and recordings only where tvOS may
delete them, and SHALL work when they are gone. A recording that tvOS deleted SHALL disappear
from the recordings list; nothing else breaks.

#### Scenario: Caches cleared
- **WHEN** tvOS removed the app's caches while it was not running
- **THEN** the app loads the channel list again and plays as usual

#### Scenario: Recording removed by tvOS
- **WHEN** tvOS deleted a finished recording's file while Fernsy was not running
- **THEN** the recordings list no longer shows it at the next launch

## ADDED Requirements

### Requirement: Navigation on Apple TV
The Apple TV app SHALL have a tab bar at the top with Live TV, Programm, Aufnahmen and a gear
for the settings, and SHALL open on Live TV once an account is signed in. Moving up from a
screen's first row SHALL reach the tab bar; Back on a tab's top level SHALL go to the tab bar
and from there leave the app as tvOS does.

#### Scenario: Switching tabs
- **WHEN** the user moves focus up to the tab bar and to "Programm"
- **THEN** the program guide shows, and Down moves focus into it

### Requirement: First launch and sign-in on Apple TV
Without an account, the Apple TV app SHALL show a welcome screen that explains that Fernsy
brings no content and lets the user choose the kind of account. The IPTV form SHALL ask for
server address, username and password, which can also be typed on a nearby iPhone, store them
in the keychain, and offer "Demo-Zugang testen", which signs in to the public demo server.
A failed sign-in SHALL say why and keep the entered values.

#### Scenario: Signing in to a provider
- **WHEN** the user enters a valid server, username and password and chooses "Anmelden"
- **THEN** the app signs in, stores the credentials in the keychain and opens Live TV

#### Scenario: Trying the demo
- **WHEN** the user chooses "Demo-Zugang testen"
- **THEN** the app signs in to the demo server and shows its channels

#### Scenario: Wrong password
- **WHEN** the provider rejects the credentials
- **THEN** the form stays open with the values entered and says that the credentials were rejected

### Requirement: Live TV on Apple TV
Live TV on Apple TV SHALL show a category column with Favoriten, Zuletzt gesehen, Alle
Sender, the pinned categories and "Alle Kategorien" with the number of categories; the
selected category's visible channels as rows; and a pane for the focused channel with the
current show, its time and description, and the next shows. Clicking a row SHALL play the
channel full screen.

#### Scenario: A channel row
- **WHEN** a channel is a favourite and is being recorded
- **THEN** its row shows number, logo, cleaned name with tags, the star, the recording mark, the current show with its progress and the time left

#### Scenario: Browsing a category
- **WHEN** the user moves focus to "Favoriten" and then into the channel rows
- **THEN** the favourite channels show with their current shows, and the pane follows the focused row

### Requirement: Live preview on Apple TV
The pane SHALL play the focused channel without sound once focus rests on its row, and
Play/Pause SHALL turn the preview's sound on and off. The preview SHALL NOT open a stream the
account's limit does not allow; then the pane shows the channel's logo and programme instead.

#### Scenario: Preview of the focused channel
- **WHEN** focus rests on a channel row
- **THEN** the pane plays that channel without sound, and Play/Pause turns the sound on

#### Scenario: Preview with a single-stream account
- **WHEN** the account allows one stream and a recording of another channel is running
- **THEN** the pane shows the channel's logo and programme instead of a preview, and no second stream is opened

### Requirement: Channel actions on Apple TV
A long press on a channel row SHALL offer Aufnehmen (or stop the recording), adding to or
removing from the favourites, and hiding the channel. Favourites, recently watched channels
and hidden channels and categories SHALL behave as in the Mac app and be kept on the Apple TV;
pinned categories SHALL be kept per account. Categories marked as adult content SHALL stay hidden, as
with the Mac app's default setting; the Apple TV app has no setting to show them.

#### Scenario: Hiding a channel
- **WHEN** the user long-presses a row and chooses "Ausblenden"
- **THEN** the channel disappears from Live TV, the guide and zapping, as in the Mac app

#### Scenario: Adding a favourite
- **WHEN** the user long-presses a row and chooses "Favorit"
- **THEN** the row shows the star and the channel is listed under "Favoriten"

### Requirement: All categories on Apple TV
"Alle Kategorien" SHALL show every live category as a tile with its country tag and channel
count, filter chips for "Alle", "Angeheftet" and each country found in the category names
(and "Ohne Land"), and a search field over the category names. Clicking a tile SHALL open the
category in Live TV. A long press SHALL pin or unpin the category in the category column, or
hide it.

#### Scenario: Filtering by country
- **WHEN** the user chooses the chip "DE"
- **THEN** only categories with the country tag DE show, with the number in the chip

#### Scenario: Pinning a category
- **WHEN** the user long-presses a tile and chooses "Anheften"
- **THEN** the category appears under "Angeheftet" in the Live TV category column

### Requirement: Program guide on Apple TV
Programm SHALL show a guide grid for a category (Favoriten by default): a channel column with
logo and name, the shows of each channel on a time axis with the current time marked, past
shows dimmed, running shows highlighted and recorded or scheduled shows marked. Focus SHALL
move show by show; clicking a running show SHALL play the channel, clicking a later show SHALL
offer to record it.

#### Scenario: Playing from the guide
- **WHEN** the user clicks a show that is running now
- **THEN** its channel plays full screen

#### Scenario: Scheduling from the guide
- **WHEN** the user clicks a show that starts later and chooses "Aufnehmen"
- **THEN** the show is scheduled and marked in the grid and in Aufnahmen

### Requirement: Player overlay on Apple TV
While a live channel plays, a click or swipe SHALL show an overlay with the channel's logo,
name and show time, the show's title, what follows, a timeline across the timeshift buffer
with its start, the playing position with its clock time, the live point and a running
recording, the time behind live, and tabs for Info, Untertitel (subtitle tracks), Ton (audio
tracks) and Sender. A running recording of the channel SHALL show as a badge.

#### Scenario: Time behind live
- **WHEN** the user went back 12 minutes and 34 seconds in the buffer
- **THEN** the overlay shows "−12:34" and the position on the timeline

### Requirement: Channel strip on Apple TV
Down in the player, or the Sender tab, SHALL slide up a strip of the category's visible
channels with now, progress and next, starting at the playing channel. Clicking one SHALL tune
it like zapping on the Mac, including the question when a recording holds the connection.

#### Scenario: Zapping from the strip
- **WHEN** the user presses Down in the player and clicks another channel in the strip
- **THEN** that channel plays, with the same tuning rules as zapping on the Mac

### Requirement: Recordings on Apple TV
The Apple TV app SHALL record a running show or the channel now, and schedule a later show,
with the padding from the settings, following the account's stream limit as the Mac app does.

#### Scenario: Recording the running show
- **WHEN** the user long-presses a channel and chooses "Aufnehmen"
- **THEN** the running show is recorded with the padding, the row shows the recording mark and Aufnahmen lists it as running

#### Scenario: Single-stream account
- **WHEN** the account allows one stream, a recording runs and the user clicks another channel
- **THEN** the app asks whether to stop the recording, as the Mac app does, and opens no second stream

### Requirement: Recording only while the app is open
Recordings on Apple TV SHALL run only while Fernsy is open: the app SHALL keep the Apple TV
awake during a recording, SHALL say so when a recording is scheduled, SHALL stop and keep a
running recording when the app is left, and SHALL mark a scheduled recording as missed when
its time passed while the app was not open.

#### Scenario: App left during a recording
- **WHEN** the user goes to the Apple TV home screen while a recording runs
- **THEN** the recording stops, and the part recorded so far is kept and marked as incomplete

#### Scenario: Missed recording
- **WHEN** a scheduled show ended while Fernsy was not open
- **THEN** Aufnahmen lists it as missed, saying the app was not open

### Requirement: Recordings list on Apple TV
Aufnahmen SHALL show running and scheduled recordings, finished ones (playable, resuming where
the user stopped) and failed or missed ones with the reason, and SHALL offer deleting them.

#### Scenario: Playing a recording
- **WHEN** the user clicks a finished recording they stopped halfway
- **THEN** it plays from where they stopped

### Requirement: Settings on Apple TV
Settings SHALL list the signed-in accounts with their state, "Konto hinzufügen", Wiedergabe
(the playback options the Mac app has), Aufnahmen (padding before and after), Protokoll (the
app log) and the app's version. Choosing an account SHALL offer signing out.

#### Scenario: Changing the padding
- **WHEN** the user sets the padding to 2 minutes before and 5 after
- **THEN** newly scheduled recordings use it, and the settings row shows "Vorlauf 2 · Nachlauf 5 Min."
