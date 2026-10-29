## Purpose
Fernsy on iPhone and iPad: what the app does, how it follows the Apple TV app and shares the
Mac app's provider, guide and playback behaviour, what it adds for touch devices and leaves out,
and how its development builds stay apart from real accounts.

## ADDED Requirements

### Requirement: iPhone and iPad app
Fernsy SHALL have one app for iPhone and iPad (iOS 27) that offers what the Apple TV app offers,
except recordings: sign-in to an Xtream account and a Jellyfin server, Start, Live TV with
programme guide, films and series, Jellyfin, search, settings and full-screen playback. It SHALL
use the Mac app's provider, guide and playback behaviour, be operated by touch, and be the same
App Store product as the Mac and Apple TV apps (universal purchase).

#### Scenario: Same behaviour as the Mac
- **WHEN** a channel plays on an iPhone
- **THEN** its name is cleaned up, reconnects are seamless and the timeshift buffer works as in the Mac app

#### Scenario: One purchase
- **WHEN** a user who owns Fernsy on the Mac opens the App Store on their iPhone
- **THEN** Fernsy shows as purchased

### Requirement: No recordings on iPhone and iPad
The iPhone and iPad app SHALL NOT record or schedule recordings: it has no Aufnahmen tab, no
record actions, no recordings row on Start and no recording settings. Showing that a channel is
being recorded on another device is not required.

#### Scenario: Show that starts later
- **WHEN** the user taps a show in the guide or in search that starts later
- **THEN** its details show, without an offer to record it

### Requirement: Storage on iPhone and iPad
The app SHALL keep the timeshift buffer and caches only where iOS may delete them, and SHALL
work when they are gone.

#### Scenario: Caches cleared
- **WHEN** iOS removed the app's caches while it was not running
- **THEN** the app loads the channel list again and plays as usual

### Requirement: Development builds of the iPhone and iPad app
Debug builds SHALL use their own bundle id and the name "Fernsy Dev", start muted, refuse to
stream from servers other than the demo server unless explicitly allowed, use a Jellyfin device
id of their own, and offer a debug MCP server on a port of their own (not the Mac's or Apple
TV's) for playing, seeking, playback state, a snapshot and the log. A script SHALL build the
app, start an iOS simulator with its window and launch the app with debug settings.

#### Scenario: Running the app on this Mac
- **WHEN** the developer runs the script with the demo account
- **THEN** the simulator window shows the app with the demo channels, without sound

#### Scenario: Real provider in a debug build
- **WHEN** a debug build is about to stream from a server that is not the demo server
- **THEN** it refuses and says so, and no stream request reaches that server

### Requirement: Navigation on iPhone and iPad
The app SHALL offer Start, Live TV, Filme, Serien, Jellyfin and Suche as tabs, plus
Einstellungen: a tab bar at the bottom on iPhone with Einstellungen behind a gear on Start (an
iPhone shows five tabs at most), and on iPad a tab bar that can turn into a sidebar with
Einstellungen as a tab. It SHALL open on Start once an account is signed in, and SHALL leave out
the tabs whose source is not signed in or switched off. The programme guide is a view of Live
TV, not a tab.

#### Scenario: Only an IPTV account
- **WHEN** only an IPTV account is signed in on an iPhone
- **THEN** the tabs are Start, Live TV, Filme, Serien and Suche, and Start has the gear for Einstellungen

#### Scenario: Only a Jellyfin account
- **WHEN** only a Jellyfin account is signed in on an iPad
- **THEN** the tabs are Start, Jellyfin, Einstellungen and Suche

#### Scenario: iPad sidebar
- **WHEN** the user opens the sidebar on an iPad
- **THEN** the same destinations show as a list, and Live TV's categories can be reached from it

### Requirement: First launch and sign-in on iPhone and iPad
Without an account, the app SHALL show a welcome screen (Fernsy brings no content) with an IPTV
account and a Jellyfin server as two cards. iCloud logins SHALL be used at launch without that
screen (icloud-sync) and offered first when it shows. Each form SHALL ask for server, username
and password, keep them in the keychain, and support password autofill. The IPTV form SHALL
offer "Demo-Zugang testen". A failed sign-in SHALL say why and keep the values.

#### Scenario: Trying the demo
- **WHEN** the user taps "Demo-Zugang testen"
- **THEN** the app signs in to the demo server and shows its channels, films and series

#### Scenario: Wrong password
- **WHEN** the provider rejects the credentials
- **THEN** the form stays open with the values entered and says that the credentials were rejected

#### Scenario: Logins from iCloud
- **WHEN** the Mac's provider login is in the user's iCloud and the app starts without an account
- **THEN** the app shows "Anmelden …" and opens Start signed in, without the welcome screen

### Requirement: Live TV on iPhone and iPad
Live TV SHALL offer the views Liste and Programm over one channel source, chosen from Favoriten,
Zuletzt gesehen, Alle Sender, the pinned categories and "Alle Kategorien". Liste SHALL show the
source's visible channels as rows with their current show; tapping a row SHALL play the channel
full screen. On iPad in landscape, a pane SHALL show the selected channel's now and next beside
the list. Source and view SHALL be kept across launches.

#### Scenario: A channel row
- **WHEN** a channel is a favourite
- **THEN** its row shows number, logo, cleaned name with tags, the star, the current show with its progress and time left, and what follows

#### Scenario: Browsing a category
- **WHEN** the user picks "Favoriten" as the source
- **THEN** the favourite channels show with their current shows

#### Scenario: Same category in both views
- **WHEN** the user picks "Sport DE" in Liste and switches to Programm
- **THEN** the guide shows the channels of "Sport DE"

#### Scenario: Kept across launches
- **WHEN** the user left Live TV in Programm with "Sport DE" and opens the app again
- **THEN** Live TV opens in Programm with "Sport DE"

### Requirement: Channel actions on iPhone and iPad
A long press (context menu) on a channel row SHALL offer adding to or removing from the
favourites and hiding the channel. Favourites, recently watched channels, hidden channels and
categories, pinned categories and adult categories SHALL behave as in the Apple TV app.

#### Scenario: Adding a favourite
- **WHEN** the user long-presses a row and chooses "Favorit"
- **THEN** the row shows the star and the channel is listed under "Favoriten"

#### Scenario: Hiding a channel
- **WHEN** the user long-presses a row and chooses "Ausblenden"
- **THEN** the channel disappears from Live TV, the guide and zapping

### Requirement: All categories on iPhone and iPad
"Alle Kategorien" SHALL show every live category with its country tag and channel count, filter
chips for "Alle", "Angeheftet" and each country found (and "Ohne Land"), and a search field over
the category names. Tapping a category SHALL open it in Live TV; a long press SHALL pin, unpin
or hide it.

#### Scenario: Filtering by country
- **WHEN** the user taps the chip "DE"
- **THEN** only categories with the country tag DE show

#### Scenario: Pinning a category
- **WHEN** the user long-presses a category and chooses "Anheften"
- **THEN** it appears among the pinned categories in Live TV's source picker

### Requirement: Program guide on iPhone and iPad
Programm SHALL show a guide grid for the chosen source that scrolls in both directions by touch:
channels with logo and name stay at the left edge, shows on a time axis with the time now marked,
past shows dimmed and running ones highlighted. Tapping a running show SHALL play its channel;
tapping a later show SHALL show its details. Rows without listings, still loading, or with gaps
SHALL show bars there that play the channel when tapped.

#### Scenario: Playing from the guide
- **WHEN** the user taps a show that is running now
- **THEN** its channel plays full screen

#### Scenario: Channel without listings
- **WHEN** the provider sends no listings for a channel
- **THEN** its row shows the bar "Keine Programmdaten", and tapping it plays the channel

### Requirement: Live player on iPhone and iPad
A live channel SHALL play full screen, in landscape on iPhone. A tap SHALL show controls that
hide after a few seconds: close, the channel's logo, name and show, play/pause, skipping back
and forward within the timeshift buffer, a timeline across the buffer that can be dragged, the
time behind live, "Live", audio and subtitle tracks, AirPlay, Picture in Picture and the channel
list. Swiping down or tapping close SHALL stop playback and return to where the channel was
started.

#### Scenario: Going back in the buffer
- **WHEN** the user drags the timeline back 12 minutes and 34 seconds
- **THEN** playback continues there and the controls show "−12:34"

#### Scenario: Closing the player
- **WHEN** the user swipes down in the player
- **THEN** playback stops and the screen it was started from shows again

#### Scenario: Orientation after the player on iPhone
- **WHEN** the user closes the player while holding the iPhone upright
- **THEN** the screen it was started from shows in portrait

### Requirement: Channel list in the player on iPhone and iPad
The player's channel list SHALL open as a panel at the side, beside the playing picture, and
show the source's visible channels with now, progress and next, starting at the playing channel. Tapping one SHALL tune it like zapping on the Mac. Swiping left or
right on the picture (controls hidden) SHALL zap to the next or previous channel of the source.

#### Scenario: Zapping from the list
- **WHEN** the user opens the channel list in the player and taps another channel
- **THEN** that channel plays, with the same tuning rules as zapping on the Mac

### Requirement: Picture in Picture on iPhone and iPad
Live channels and on-demand items SHALL be able to continue in Picture in Picture: from the
player's button, and automatically when the user leaves the app while playing. Playback SHALL
continue with sound while in Picture in Picture; returning from it SHALL show the full-screen
player again.

#### Scenario: Leaving the app while watching
- **WHEN** a channel plays full screen and the user goes to the home screen
- **THEN** the channel continues in a Picture in Picture window with sound

#### Scenario: Back from Picture in Picture
- **WHEN** the user taps the button to return in the Picture in Picture window
- **THEN** Fernsy opens with the player full screen, still playing

### Requirement: AirPlay on iPhone and iPad
The player SHALL offer the system's AirPlay picker. When an AirPlay speaker is chosen the sound
SHALL play there. When the device mirrors its screen to an AirPlay screen, the player SHALL show
there full screen with the sound.

#### Scenario: Sending the sound to a speaker
- **WHEN** the user picks an AirPlay speaker while a channel plays
- **THEN** the sound plays on the speaker and the picture stays on the phone

#### Scenario: Watching on an AirPlay screen
- **WHEN** the user mirrors the iPhone to an Apple TV while a film plays
- **THEN** the film's picture and sound show on the TV

### Requirement: Start on iPhone and iPad
Start SHALL show a large entry (the newest item to continue with "Fortsetzen", else the newest
film with "Abspielen") and below it, each only with entries: Jetzt live, Weiterschauen, Nächste
Folge (Jellyfin), Heute Abend, Zuletzt hinzugefügt, rows of the largest film and series
categories and Jellyfin genres, and Bestbewertet. Rows SHALL scroll sideways; tapping an entry
SHALL play it or open its page.

#### Scenario: Resuming from Start
- **WHEN** the user taps a partly watched film in "Weiterschauen"
- **THEN** it plays from where the user stopped

#### Scenario: Live from Start
- **WHEN** the user taps a channel in "Jetzt live"
- **THEN** the channel plays full screen

### Requirement: Films and series on iPhone and iPad
Filme and Serien SHALL show the IPTV account's films or series as poster grids that fit the
screen width, with title, rating, "Neu", resume progress and watched marks, a category picker and
the sorting Zuletzt hinzugefügt, A–Z, Bewertung and Erscheinungsjahr. Film and series pages SHALL
show what the Apple TV app's pages show, with the same resume, "Von vorn", favourite, season and
next-episode behaviour.

#### Scenario: Sorting by rating
- **WHEN** the user chooses "Bewertung"
- **THEN** the grid shows the highest rated items first

#### Scenario: Next episode
- **WHEN** the user opens a series whose S2 F3 is watched and S2 F4 is partly watched
- **THEN** the page offers "Nächste Episode · S2 F4" and selects Staffel 2

### Requirement: Jellyfin on iPhone and iPad
The Jellyfin tab SHALL show the server's name and state and the views Übersicht, Filme, Serien and
Bibliotheken as in the Apple TV app. Watched state and favourites changed on the iPhone or iPad
SHALL be written to the server. The app SHALL appear on the server as a device of its own, named
after the iPhone or iPad.

#### Scenario: Server not reachable
- **WHEN** the Jellyfin server cannot be reached
- **THEN** the tab shows the cached lists and says that the server is not reachable

### Requirement: Search on iPhone and iPad
Suche SHALL take the query from the system search field (keyboard and dictation) and update the
results while typing. Results SHALL show live TV shows that run now or later, and films and
series from the IPTV account and Jellyfin with their source, following the Mac's search rules.
Tapping a running show SHALL play its channel, a later one SHALL show its details, and a film or
series SHALL open its page.

#### Scenario: Searching across sources
- **WHEN** the user types "kart"
- **THEN** live TV, IPTV and Jellyfin results containing "kart" show, each marked with its source

### Requirement: On-demand playback on iPhone and iPad
Films, episodes and Jellyfin items SHALL play full screen with resume, audio and subtitle tracks,
a draggable timeline with the time left, skipping back and forward, and the next-episode
countdown, as in the Apple TV app. Jellyfin items SHALL play directly or transcoded under the
Mac's rules and report start, progress and stop to the server.

#### Scenario: Jellyfin progress
- **WHEN** the user stops a Jellyfin film after 20 minutes
- **THEN** the server's resume position is about 20 minutes, and Start shows the film in "Weiterschauen"

#### Scenario: Next episode countdown
- **WHEN** an episode ends and the next one exists
- **THEN** the player shows the next episode with a countdown that starts it

### Requirement: Player status and errors on iPhone and iPad
The player SHALL show loading, buffering and reconnecting states, the stall cause (provider too
slow, no internet) and failure cards with "Erneut versuchen" and, for live channels, "Nächster
Sender", as the Apple TV app does.

#### Scenario: Offline channel
- **WHEN** a live channel turns out to be offline at the provider
- **THEN** a card says so and offers "Erneut versuchen" and "Nächster Sender"

### Requirement: Settings on iPhone and iPad
Einstellungen SHALL list the signed-in accounts with their state and signing out, "Konto
hinzufügen", the IPTV account's switches "Filme" and "Serien", Wiedergabe (the Mac's playback
options and "Technische Infos"), iCloud (the sync switches and whether iCloud is available),
Protokoll (the app log) and the app's version.

#### Scenario: Turning on technical information
- **WHEN** the user turns on "Technische Infos" and plays a channel
- **THEN** the player shows the technical information panel as on Apple TV, updated every second

#### Scenario: Switching films off
- **WHEN** the user switches "Filme" off
- **THEN** the Filme tab disappears, and Start and the search show no provider films
