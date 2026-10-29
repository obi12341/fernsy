## MODIFIED Requirements

### Requirement: Navigation on Apple TV
The Apple TV app SHALL have a tab bar at the top with Start, Live TV, Filme, Serien, Jellyfin,
Aufnahmen, a search icon and a gear for the settings, SHALL open on Start once an account is
signed in, and SHALL leave out the tabs whose source is not signed in. The program guide is a
view of Live TV, not a tab. Moving up from a screen's first row SHALL reach the tab bar; Back on
a tab's top level SHALL go to the tab bar. Up and Down on card rows SHALL move one row at a time.

#### Scenario: Only an IPTV account
- **WHEN** only an IPTV account is signed in
- **THEN** the tab bar shows all tabs except Jellyfin

#### Scenario: Switching tabs
- **WHEN** the user moves focus up to the tab bar and to "Live TV"
- **THEN** Live TV shows in the view used last, and Down moves focus into it

#### Scenario: Only a Jellyfin account
- **WHEN** only a Jellyfin account is signed in
- **THEN** the tab bar shows Start, Jellyfin, search and the gear

#### Scenario: Down onto a shorter row
- **WHEN** the fourth card of a row has focus, the row below has three cards, and the user presses Down
- **THEN** focus moves to the last card of the row below, not to a row further down
