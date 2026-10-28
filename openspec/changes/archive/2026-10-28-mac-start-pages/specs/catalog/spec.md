## MODIFIED Requirements

### Requirement: Library sections and categories
The sidebar SHALL list Start at the top, selected when the app opens. With an IPTV account it
SHALL list Live TV, Movies, Series, Favorites and Recordings, leaving out Movies or Series while
switched off; with a Jellyfin account also the Jellyfin group. The second column SHALL list the
section's categories with item counts, an "All" entry and a filter field. Recordings SHALL show
how many run ("1 läuft"); the sidebar footer the IPTV server, expiry date and last catalog update.

#### Scenario: Choosing a category
- **WHEN** the user selects a category in the Movies section
- **THEN** only the movies of that category are shown

#### Scenario: Only a Jellyfin account
- **WHEN** the user is signed in to Jellyfin but not to IPTV
- **THEN** the sidebar shows Start and the Jellyfin group

#### Scenario: Recording in progress
- **WHEN** a recording runs
- **THEN** the Recordings entry in the sidebar shows "1 läuft" in red next to its name

#### Scenario: Series switched off
- **WHEN** "Serien" is switched off in Settings › Accounts
- **THEN** the IPTV group lists Live TV, Movies, Favorites and Recordings

#### Scenario: Opening the app
- **WHEN** the user opens the library window
- **THEN** Start is selected

## ADDED Requirements

### Requirement: Start on the Mac
Start SHALL show the rows of Start on Apple TV, built by the same rules: the large entry over its
backdrop, then Jetzt live, Weiterschauen, Nächste Folge, Heute Abend, Zuletzt hinzugefügt, the
largest categories and genres, Deine Aufnahmen and Bestbewertet, each only with entries. Rows
SHALL page with previous/next buttons. While the pointer is over the large entry, its backdrop
SHALL move as on Apple TV; otherwise it SHALL rest.

#### Scenario: Continue from Start
- **WHEN** the user clicks "Fortsetzen" on the large entry for a partly watched film
- **THEN** the film plays in the player window from where the user stopped

#### Scenario: Live from Start
- **WHEN** the user clicks a channel in "Jetzt live"
- **THEN** the channel plays in the player window

#### Scenario: A later show
- **WHEN** the user clicks a show in "Heute Abend" that starts later
- **THEN** the app offers to record it

#### Scenario: Pointer over the large entry
- **WHEN** the pointer rests over the large entry
- **THEN** its backdrop zooms and pans slowly and stops when the pointer leaves

#### Scenario: Same rows on both devices
- **WHEN** the Mac and the Apple TV use the same IPTV account and Jellyfin server
- **THEN** Start lists the same rows in the same order on both
