## MODIFIED Requirements

### Requirement: Jellyfin overview on Apple TV
Übersicht SHALL show, from the loaded library: a spotlight on an unwatched, well-rated film with
"Abspielen", "Anderer Vorschlag" and "Details"; Weiterschauen; Nächste Folge (the server's next
episodes, as on Start); Zuletzt hinzugefügt; Deine Favoriten; Ungesehen & top bewertet; Kurz &
gut; Serien fast durch; Wieder entdecken; tiles per genre and decade that open their titles; and
the library in numbers. Rows without entries SHALL be left out.

#### Scenario: Another suggestion
- **WHEN** the user chooses "Anderer Vorschlag" in the spotlight
- **THEN** another unwatched, well-rated film takes its place

#### Scenario: Browsing a genre
- **WHEN** the user clicks the tile "Komödie"
- **THEN** a grid shows the library's comedies, and Back returns to Übersicht

#### Scenario: A series almost finished
- **WHEN** the user has watched all but two episodes of a series
- **THEN** it shows under "Serien fast durch" with "2 Folgen übrig"

#### Scenario: Next episode of a series
- **WHEN** the user has watched episode 3 of a series to its end
- **THEN** "Nächste Folge" below Weiterschauen shows episode 4 of that series, and selecting it plays the episode
