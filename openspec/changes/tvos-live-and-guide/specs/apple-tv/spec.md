## MODIFIED Requirements

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

### Requirement: Program guide on Apple TV
Live TV's Programm view SHALL show a guide grid for the chosen source: a channel column with
logo and name, the shows on a time axis with the current time marked, past shows dimmed,
running shows highlighted and recorded or scheduled shows marked. The category column SHALL
narrow to a rail with the source's name and open again by moving left. Clicking a running show
SHALL play the channel, a later one SHALL offer to record it.

#### Scenario: Playing from the guide
- **WHEN** the user clicks a show that is running now
- **THEN** its channel plays full screen

#### Scenario: Scheduling from the guide
- **WHEN** the user clicks a show that starts later and chooses "Aufnehmen"
- **THEN** the show is scheduled and marked in the grid and in Aufnahmen

#### Scenario: Changing the category in the guide
- **WHEN** the user moves left from the guide's channel column and clicks "Favoriten"
- **THEN** the column narrows again and the guide shows the favourite channels

#### Scenario: Any category in the guide
- **WHEN** the user opens "Alle Kategorien" from the guide and clicks a category that is not pinned
- **THEN** the guide shows that category's channels
