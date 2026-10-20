## Purpose

Lets the user browse the films and series of their Jellyfin server in Fernsy: libraries,
genres, home rows, details, watched status and favorites.

## ADDED Requirements

### Requirement: Jellyfin group in the sidebar
With a Jellyfin account the sidebar SHALL show a "Jellyfin" group with Home, Films and Series.
Music, live TV and other library types are not shown.

#### Scenario: Server with film, series and music libraries
- **WHEN** the server has libraries of type films, series and music
- **THEN** the group offers Home, Films and Series only

### Requirement: Libraries and genres as categories
For Films and Series the category column SHALL list "All", "Favorites", each library of that
type and the genres occurring in it, with item counts and the existing filter field.

#### Scenario: Two film libraries
- **WHEN** the server has the film libraries "Movies" and "Kids"
- **THEN** the category column lists All, Favorites, Movies, Kids and the genres

### Requirement: Poster grids with sorting and search
Films and series SHALL be shown as poster grids with title, year and rating, sortable by
recently added, name, release date and rating; the toolbar search filters by title.

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

### Requirement: Home rows
Home SHALL show "Continue Watching" (partly watched films and episodes) and "Next Up" (next
unwatched episode of series in progress) from the server, followed by "Recently Added" for
films and series. Home has no category column; each row pages with previous/next buttons,
so no horizontal scroll wheel is needed. Without the server, the rows come from the cached library.

#### Scenario: Paging with a mouse
- **WHEN** the user clicks the next button of "New Movies" with a mouse that only scrolls vertically
- **THEN** the row moves on by one page of posters

#### Scenario: Series in progress
- **WHEN** the user watched episode 4 of a series on another client
- **THEN** episode 5 appears under Next Up

### Requirement: Playback is announced but not available yet
Play buttons for Jellyfin items SHALL be visible but disabled, with a hint that playback
follows in a later version.

#### Scenario: Pressing Play
- **WHEN** the user looks at the Play button of a Jellyfin film
- **THEN** it is disabled and its help text says playback is not available yet

### Requirement: Cached library, refreshed in the background
The film and series lists SHALL be shown from a local cache at launch and refreshed in the
background; watched status and favorites SHALL be refreshed when a Jellyfin section opens.
A server that is not reachable keeps the cached library usable with a notice.

#### Scenario: Server offline
- **WHEN** the Jellyfin server is not reachable at launch
- **THEN** the cached films and series are shown with a notice that the server is offline
