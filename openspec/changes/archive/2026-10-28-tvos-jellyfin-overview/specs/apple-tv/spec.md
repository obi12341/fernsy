## MODIFIED Requirements

### Requirement: Jellyfin on Apple TV
The Jellyfin tab SHALL show the server's name and state and the views Übersicht, Filme, Serien
and Bibliotheken. Übersicht SHALL be the library's discovery page (see "Jellyfin overview on
Apple TV"); Filme and Serien SHALL be poster grids as on the Mac; Bibliotheken SHALL list the
server's film and series libraries. Watched state and favourites changed on Apple TV SHALL be
written to the server.

#### Scenario: Server not reachable
- **WHEN** the Jellyfin server cannot be reached
- **THEN** the tab shows the cached lists and says that the server is not reachable

## ADDED Requirements

### Requirement: Jellyfin overview on Apple TV
Übersicht SHALL show, from the loaded library: a spotlight on an unwatched, well-rated film with
"Abspielen", "Anderer Vorschlag" and "Details"; Weiterschauen; Zuletzt hinzugefügt; Deine
Favoriten; Ungesehen & top bewertet; Kurz & gut; Serien fast durch; Wieder entdecken; tiles per
genre and decade that open their titles; and the library in numbers. Rows without entries SHALL
be left out.

#### Scenario: Another suggestion
- **WHEN** the user chooses "Anderer Vorschlag" in the spotlight
- **THEN** another unwatched, well-rated film takes its place

#### Scenario: Browsing a genre
- **WHEN** the user clicks the tile "Komödie"
- **THEN** a grid shows the library's comedies, and Back returns to Übersicht

#### Scenario: A series almost finished
- **WHEN** the user has watched all but two episodes of a series
- **THEN** it shows under "Serien fast durch" with "2 Folgen übrig"
