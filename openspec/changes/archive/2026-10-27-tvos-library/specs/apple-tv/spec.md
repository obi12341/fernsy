## MODIFIED Requirements

### Requirement: Navigation on Apple TV
The Apple TV app SHALL have a tab bar at the top with Start, Live TV, Programm, Filme, Serien,
Jellyfin, Aufnahmen, a search icon and a gear for the settings, SHALL open on Start once an
account is signed in, and SHALL leave out the tabs whose source is not signed in. Moving up from
a screen's first row SHALL reach the tab bar; Back on a tab's top level SHALL go to the tab bar.

#### Scenario: Only an IPTV account
- **WHEN** only an IPTV account is signed in
- **THEN** the tab bar shows all tabs except Jellyfin

#### Scenario: Switching tabs
- **WHEN** the user moves focus up to the tab bar and to "Programm"
- **THEN** the program guide shows, and Down moves focus into it

#### Scenario: Only a Jellyfin account
- **WHEN** only a Jellyfin account is signed in
- **THEN** the tab bar shows Start, Jellyfin, search and the gear

### Requirement: First launch and sign-in on Apple TV
Without an account, the Apple TV app SHALL show a welcome screen that explains that Fernsy
brings no content and offers an IPTV account and a Jellyfin server as two cards. Each form SHALL
ask for server address, username and password (typing on a nearby iPhone works) and keep them in
the keychain; the IPTV form SHALL also offer "Demo-Zugang testen". A failed sign-in SHALL say why
and keep the entered values.

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

## ADDED Requirements

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
