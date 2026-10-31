## MODIFIED Requirements

### Requirement: Jellyfin overview on the Mac
Übersicht SHALL show the server's name and state, then the content of Jellyfin's Übersicht on
Apple TV, built by the same rules: the suggestion with "Abspielen", "Anderer Vorschlag" and
"Details", Weiterschauen, Nächste Folge, Zuletzt hinzugefügt, the discovery rows, genre and
decade tiles that open a sortable grid, and the library in numbers. Rows without entries SHALL be
left out and rows SHALL page with previous/next buttons. Without the server, it SHALL use the
cached library.

#### Scenario: Another suggestion
- **WHEN** the user clicks "Anderer Vorschlag"
- **THEN** another unwatched, well-rated film takes the suggestion's place

#### Scenario: Browsing a decade
- **WHEN** the user clicks the tile "1990er"
- **THEN** a grid shows the library's titles from the 1990s, sortable by rating, name and year

#### Scenario: Paging with a mouse
- **WHEN** the user clicks the next button of a row with a mouse that only scrolls vertically
- **THEN** the row moves on by one page

#### Scenario: Next episode on the Mac
- **WHEN** a series has a next episode on the server
- **THEN** "Nächste Folge" shows it below Weiterschauen, and clicking it plays the episode
