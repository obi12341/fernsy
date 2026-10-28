# apple-tv Specification

## Purpose
Fernsy on Apple TV: what the Apple TV app does, how it shares the Mac app's provider, guide
and playback behavior, what tvOS limits, and how its development builds stay apart from
real accounts.

## Requirements

### Requirement: Apple TV app
Fernsy SHALL have an app for Apple TV 4K (tvOS 27) that signs in to an Xtream account, shows
its live channels by category with now and next, a program guide and recordings, and plays a
live channel full screen with pause, skipping within the timeshift buffer, back to live and
zapping. It SHALL use the Mac app's provider, guide and playback behavior and be operated with
the Siri Remote alone.

#### Scenario: Same behavior as the Mac
- **WHEN** a channel plays on Apple TV
- **THEN** its name is cleaned up, reconnects are seamless and the timeshift buffer works as in the Mac app

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

### Requirement: Navigation on Apple TV
The Apple TV app SHALL have a tab bar at the top with Start, Live TV, Filme, Serien, Jellyfin,
Aufnahmen, a search icon and a gear for the settings, SHALL open on Start once an account is
signed in, and SHALL leave out the tabs whose source is not signed in. The program guide is a
view of Live TV, not a tab. Moving up from a screen's first row SHALL reach the tab bar; Back on
a tab's top level SHALL go to the tab bar.

#### Scenario: Only an IPTV account
- **WHEN** only an IPTV account is signed in
- **THEN** the tab bar shows all tabs except Jellyfin

#### Scenario: Switching tabs
- **WHEN** the user moves focus up to the tab bar and to "Live TV"
- **THEN** Live TV shows in the view used last, and Down moves focus into it

#### Scenario: Only a Jellyfin account
- **WHEN** only a Jellyfin account is signed in
- **THEN** the tab bar shows Start, Jellyfin, search and the gear

### Requirement: First launch and sign-in on Apple TV
Without an account, the Apple TV app SHALL show a welcome screen that explains that Fernsy
brings no content and offers an IPTV account and a Jellyfin server as two cards; logins found in
the user's iCloud SHALL be offered first. Each form SHALL ask for server address, username and
password (typing on a nearby iPhone works) and keep them in the keychain; the IPTV form SHALL
also offer "Demo-Zugang testen". A failed sign-in SHALL say why and keep the entered values.

#### Scenario: Adding the other account
- **WHEN** an IPTV account is signed in and the user opens Settings › Konto hinzufügen
- **THEN** the Jellyfin server is offered, and signing in adds the Jellyfin tab

#### Scenario: Signing in to a provider
- **WHEN** the user enters a valid server, username and password and chooses "Anmelden"
- **THEN** the app signs in, stores the credentials in the keychain and opens Start

#### Scenario: Trying the demo
- **WHEN** the user chooses "Demo-Zugang testen"
- **THEN** the app signs in to the demo server and shows its channels, films and series

#### Scenario: Wrong password
- **WHEN** the provider rejects the credentials
- **THEN** the form stays open with the values entered and says that the credentials were rejected

#### Scenario: Signing in to Jellyfin
- **WHEN** the user chooses the Jellyfin card and signs in to a Jellyfin server
- **THEN** the Jellyfin tab appears and the session is kept in the keychain

#### Scenario: Logins from iCloud
- **WHEN** the Mac's provider login is in the user's iCloud and the Apple TV app starts without an account
- **THEN** the welcome screen shows the provider's server and user with "Übernehmen", which signs in without the form

### Requirement: Live TV on Apple TV
Live TV on Apple TV SHALL offer the views Liste and Programm over one channel source, chosen
in a category column (Favoriten, Zuletzt gesehen, Alle Sender, the pinned categories, "Alle
Kategorien") by clicking an entry, not by moving focus over it. Liste SHALL show the source's
visible channels as rows and a pane for the focused channel with now and next; clicking a row
SHALL play it full screen. Source and view SHALL be kept across launches.

#### Scenario: A channel row
- **WHEN** a channel is a favourite and is being recorded
- **THEN** its row shows number, logo, cleaned name with tags, the star, the recording mark, the current show with its progress and the time left

#### Scenario: Browsing a category
- **WHEN** the user clicks "Favoriten" in the column and moves into the channel rows
- **THEN** the favourite channels show with their current shows, and the pane follows the focused row

#### Scenario: Moving through the column
- **WHEN** focus moves from "Alle Sender" down past "Favoriten" without a click
- **THEN** the rows still show all channels

#### Scenario: Same category in both views
- **WHEN** the user clicks the category "Sport DE" in Liste and switches to Programm
- **THEN** the guide shows the channels of "Sport DE"

#### Scenario: Kept across launches
- **WHEN** the user left Live TV in Programm with "Sport DE" and opens the app again
- **THEN** Live TV opens in Programm with "Sport DE"

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
Live TV's Programm view SHALL show a guide grid for the chosen source: a channel column with
logo and name, the shows on a time axis with the current time marked, past shows dimmed,
running shows highlighted and recorded or scheduled shows marked. The category column SHALL
narrow to a rail with the source's name that opens the column when clicked. Clicking a running
show SHALL play the channel, a later one SHALL offer to record it.

#### Scenario: Playing from the guide
- **WHEN** the user clicks a show that is running now
- **THEN** its channel plays full screen

#### Scenario: Scheduling from the guide
- **WHEN** the user clicks a show that starts later and chooses "Aufnehmen"
- **THEN** the show is scheduled and marked in the grid and in Aufnahmen

#### Scenario: Changing the category in the guide
- **WHEN** the user moves left to the rail, clicks it and clicks "Favoriten"
- **THEN** the column narrows again and the guide shows the favourite channels

#### Scenario: Any category in the guide
- **WHEN** the user opens "Alle Kategorien" from the guide and clicks a category that is not pinned
- **THEN** the guide shows that category's channels

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
(the playback options the Mac app has), Aufnahmen (padding before and after), iCloud (the two
sync switches and whether iCloud is available), Protokoll (the app log) and the app's version.
Choosing an account SHALL offer signing out.

#### Scenario: Changing the padding
- **WHEN** the user sets the padding to 2 minutes before and 5 after
- **THEN** newly scheduled recordings use it, and the settings row shows "Vorlauf 2 · Nachlauf 5 Min."

#### Scenario: iCloud not available
- **WHEN** the Apple TV is not signed in to iCloud
- **THEN** Settings › iCloud says that syncing needs iCloud, and the app keeps working with its own values

### Requirement: Start on Apple TV
Start SHALL show the most recent item to continue as a large entry with its backdrop, kind,
title, facts and "Fortsetzen · noch <time>", a "Weiterschauen" row with partly watched IPTV
films and episodes, Jellyfin items and recordings, each with its source and progress, newest
first, and a "Zuletzt hinzugefügt" row from the IPTV account and Jellyfin. Clicking an item
SHALL resume it; the info button and a long press SHALL open its page.

#### Scenario: Resuming from Start
- **WHEN** the user clicks a partly watched film in "Weiterschauen"
- **THEN** it plays from where the user stopped

#### Scenario: Nothing to continue
- **WHEN** nothing is partly watched
- **THEN** Start shows "Zuletzt hinzugefügt" at the top and no large entry

### Requirement: Films and series on Apple TV
Filme and Serien SHALL show the IPTV account's films or series as poster grids with title,
rating, "Neu" for recently added items, the resume progress and watched marks, a category
picker ("Kategorie: Alle" and the provider's categories) and the sorting Zuletzt hinzugefügt,
A–Z, Bewertung and Erscheinungsjahr. Hidden and adult categories SHALL be treated as on the
Mac.

#### Scenario: Sorting by rating
- **WHEN** the user chooses "Bewertung"
- **THEN** the grid shows the highest rated items first

### Requirement: Film page on Apple TV
A film page SHALL show backdrop, title, year, genre, runtime, rating, quality and age rating
where known, the description, "Fortsetzen · <position>" with the progress and the time left
(or "Abspielen"), "Von vorn", the favourite star, and director, cast, audio and subtitle
languages. Resume positions and favourites SHALL come from Jellyfin for Jellyfin items and be
kept per account on the Apple TV for IPTV items.

#### Scenario: Starting over
- **WHEN** the user chooses "Von vorn" on a partly watched film
- **THEN** it plays from the beginning

### Requirement: Series page on Apple TV
A series page SHALL show its source, the number of seasons, the description, "Nächste Episode
· S<n> F<n>", the favourite star, a season picker and the season's episodes with number,
runtime, title, watched mark, "Als Nächstes" and progress. Watched state SHALL come from
Jellyfin for Jellyfin series and be kept per account on the Apple TV for IPTV series.

#### Scenario: Next episode
- **WHEN** the user opens a series whose S2 F3 is watched and S2 F4 is partly watched
- **THEN** the page offers "Nächste Episode · S2 F4", selects Staffel 2 and marks S2 F4 "Als Nächstes"

### Requirement: Jellyfin on Apple TV
The Jellyfin tab SHALL show the server's name and state and the views Übersicht, Filme, Serien
and Bibliotheken. Übersicht SHALL show "Weiterschauen" and "Zuletzt hinzugefügt" with the
number of unwatched episodes on series; Filme and Serien SHALL be poster grids as on the Mac;
Bibliotheken SHALL list the server's film and series libraries. Watched state and favourites
changed on Apple TV SHALL be written to the server.

#### Scenario: Server not reachable
- **WHEN** the Jellyfin server cannot be reached
- **THEN** the tab shows the cached lists and says that the server is not reachable

### Requirement: Jellyfin device on Apple TV
The Apple TV app SHALL appear on the Jellyfin server as a device of its own, named after the
Apple TV, and debug builds SHALL use a device id of their own, so signing in or out on one
device never ends another device's session.

#### Scenario: Debug sign-in next to the Mac
- **WHEN** a debug build of the Apple TV app signs in to a server the Mac app is signed in to
- **THEN** the server lists both devices and the Mac app stays signed in

### Requirement: Search input on Apple TV
Search SHALL take the query from an on-screen letter row (a–z, ä, ö, ü, space and delete),
from dictation with the Siri button, or typed on the iPhone, and SHALL update the results while
typing.

#### Scenario: Typing with the letter row
- **WHEN** the user clicks k, a, r, t in the letter row
- **THEN** the query reads "kart" and the results update after each letter

### Requirement: Search results on Apple TV
Results SHALL show live TV shows that run now or later, with channel, time and whether they
run now, and films and series from the IPTV account and Jellyfin with their source, following
the Mac's search rules for matching, order and what it leaves out. Clicking a show that runs
now SHALL play its channel, a later one SHALL offer to record it, a film or series SHALL open
its page.

#### Scenario: Searching across sources
- **WHEN** the user types "kart"
- **THEN** live TV, IPTV and Jellyfin results containing "kart" show, each marked with its source

### Requirement: On-demand playback on Apple TV
Films, episodes and Jellyfin items SHALL play full screen in the Apple TV player with resume,
audio and subtitle tracks, a timeline with the time left, and the next-episode countdown, as in
the Mac app. Jellyfin items SHALL play directly or transcoded under the Mac's rules and report
start, progress and stop to the server. An IPTV episode played to its end SHALL count as
watched.

#### Scenario: Jellyfin progress
- **WHEN** the user stops a Jellyfin film after 20 minutes
- **THEN** the server's resume position is about 20 minutes, and Start shows the film in "Weiterschauen"

#### Scenario: Next episode countdown
- **WHEN** an episode ends and the next one exists
- **THEN** the player shows the next episode with a countdown that starts it

### Requirement: Text fields on Apple TV
Text fields in the Apple TV app (the sign-in forms, the search field and the categories search)
SHALL look as in the design and show no system field platter: a sign-in field is a card with its
label over the value, the password as dots and the label alone when empty, and lifts and turns
light on focus. Selecting a field SHALL open tvOS' text entry (keyboard, dictation, typing on a
nearby iPhone) and the entered text SHALL show in the field afterwards.

#### Scenario: Focusing a sign-in field
- **WHEN** the focus moves to "Server Address" on the IPTV sign-in form
- **THEN** the field's card lifts and turns light, and no second shape or white bar appears inside it

#### Scenario: Entering a value
- **WHEN** the user selects "Username", types "demo" and returns
- **THEN** the card shows "demo" under its label

#### Scenario: Password stays hidden
- **WHEN** a password has been entered
- **THEN** the field shows dots, not the password

#### Scenario: Typing on the iPhone
- **WHEN** the user selects a sign-in field while an iPhone is nearby
- **THEN** the iPhone offers to type into it, as with a system text field

#### Scenario: Search field
- **WHEN** the user moves down from the letter row to the search field and selects it
- **THEN** tvOS' text entry opens, and the query typed there updates the results

### Requirement: Technical information on Apple TV
Settings › Wiedergabe SHALL offer "Technische Infos", off by default. While it is on, every
player on Apple TV SHALL show a panel with the rows of the Mac's technical information overlay
and its two-minute buffer chart, updated once per second, without taking the focus or hiding
the player overlay. The setting SHALL be kept across launches.

#### Scenario: Turning it on
- **WHEN** the user turns on "Technische Infos" and plays a live channel
- **THEN** the panel shows codec, resolution, decoder, buffer and reconnects and updates every second

#### Scenario: Reconnect counted
- **WHEN** a live stream reconnects and repeats packets it already sent
- **THEN** the panel counts the seamless reconnect and the dropped duplicates, as on the Mac

#### Scenario: Off by default
- **WHEN** the app is installed and a film plays
- **THEN** no panel is shown

#### Scenario: Remote still works
- **WHEN** the panel is shown and the user clicks to open the player overlay
- **THEN** the overlay opens and takes the focus as without the panel
