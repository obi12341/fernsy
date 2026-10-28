# jellyfin-library Specification

## Purpose
Lets the user browse the films and series of their Jellyfin server in Fernsy: libraries,
genres, home rows, details, watched status and favorites.

## Requirements

### Requirement: Jellyfin group in the sidebar
With a Jellyfin account the sidebar SHALL show a "Jellyfin" group with Übersicht, Films and
Series. Music, live TV and other library types are not shown. The group's header SHALL show the
server's state with a dot and text: the server name while it is reachable, "Offline" while
it is not.

#### Scenario: Server with film, series and music libraries
- **WHEN** the server has libraries of type films, series and music
- **THEN** the group offers Übersicht, Films and Series only

#### Scenario: Server unreachable
- **WHEN** the Jellyfin server cannot be reached
- **THEN** the group header shows an amber dot with "Offline"

### Requirement: Libraries and genres as categories
For Films and Series the category column SHALL list "All", "Favorites", each library of that
type and the genres occurring in it, with item counts and the existing filter field.

#### Scenario: Two film libraries
- **WHEN** the server has the film libraries "Movies" and "Kids"
- **THEN** the category column lists All, Favorites, Movies, Kids and the genres

### Requirement: Poster grids with sorting
Films and series SHALL be shown as poster grids with title, year and rating, sortable by
recently added, name, release date and rating through a visible segment. Searching by title happens in the search across
all sources.

#### Scenario: Sorting by release date
- **WHEN** the user sorts films by release date
- **THEN** the newest releases come first

### Requirement: Watched status on posters
Posters and episodes SHALL show the server's watched status: a check mark when played, a
progress bar when partly watched, and for series the number of unwatched episodes.

#### Scenario: Partly watched film
- **WHEN** a film was stopped at 40 % on another Jellyfin client
- **THEN** its poster shows a progress bar at 40 %

### Requirement: Mark as watched or unwatched
Context menus and detail views SHALL offer "Mark as Watched"/"Mark as Unwatched" for films,
series, seasons and episodes; the change is written to the server and shown immediately.

#### Scenario: Marking a season
- **WHEN** the user marks season 2 of a series as watched
- **THEN** all its episodes show a check mark and the server reports them as played

### Requirement: Jellyfin favorites
Films and series SHALL be markable as Jellyfin favorites (star), stored on the server; the
"Favorites" category lists them.

#### Scenario: Favorite set in the web client
- **WHEN** a film was made a favorite in Jellyfin's web client
- **THEN** it appears under Films › Favorites in Fernsy with a filled star

### Requirement: Film detail
The film detail view SHALL show backdrop, poster, title, year, runtime, rating, genres,
overview, director and cast, the available versions' video/audio/subtitle languages, the
watched state, the favorite star and a Play button.

#### Scenario: Opening a film
- **WHEN** the user opens a film
- **THEN** its details and artwork are shown

### Requirement: Series detail
The series detail view SHALL show the series information, its seasons and, for the selected
season, the episodes with number, title, runtime, overview, thumbnail and watched state.

#### Scenario: Choosing a season
- **WHEN** the user selects season 3
- **THEN** the episodes of season 3 are listed in order

### Requirement: Cached library, refreshed in the background
The film and series lists SHALL be shown from a local cache at launch and refreshed in the
background; watched status and favorites SHALL be refreshed when a Jellyfin section opens.
A server that is not reachable keeps the cached library usable with an amber notice
("Jellyfin nicht erreichbar", the saved library is shown, "Retry"), and the sidebar and the
Übersicht header say "Offline" at the same time.

#### Scenario: Server offline
- **WHEN** the Jellyfin server is not reachable at launch
- **THEN** the cached films and series are shown with a notice that the server is offline

### Requirement: Jellyfin overview on the Mac
Übersicht SHALL show the server's name and state, then the content of Jellyfin's Übersicht on
Apple TV, built by the same rules: the suggestion with "Abspielen", "Anderer Vorschlag" and
"Details", Weiterschauen, Zuletzt hinzugefügt, the discovery rows, genre and decade tiles that
open a sortable grid, and the library in numbers. Rows without entries SHALL be left out and
rows SHALL page with previous/next buttons. Without the server, it SHALL use the cached library.

#### Scenario: Another suggestion
- **WHEN** the user clicks "Anderer Vorschlag"
- **THEN** another unwatched, well-rated film takes the suggestion's place

#### Scenario: Browsing a decade
- **WHEN** the user clicks the tile "1990er"
- **THEN** a grid shows the library's titles from the 1990s, sortable by rating, name and year

#### Scenario: Paging with a mouse
- **WHEN** the user clicks the next button of a row with a mouse that only scrolls vertically
- **THEN** the row moves on by one page
