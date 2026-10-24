## MODIFIED Requirements

### Requirement: Poster grids with sorting
Films and series SHALL be shown as poster grids with title, year and rating, sortable by
recently added, name, release date and rating through a visible segment. Searching by title happens in the search across
all sources.

#### Scenario: Sorting by release date
- **WHEN** the user sorts films by release date
- **THEN** the newest releases come first

### Requirement: Home rows
Home SHALL show the server's name and state at the top, then "Continue Watching" (partly
watched films and episodes, as wide cards with a progress bar) and "Next Up" (next
unwatched episode of series in progress) from the server, followed by "Recently Added" for
films and series. Home has no category column; each row pages with previous/next buttons,
so no horizontal scroll wheel is needed. Without the server, the rows come from the cached library.

#### Scenario: Paging with a mouse
- **WHEN** the user clicks the next button of "New Movies" with a mouse that only scrolls vertically
- **THEN** the row moves on by one page of posters

#### Scenario: Series in progress
- **WHEN** the user watched episode 4 of a series on another client
- **THEN** episode 5 appears under Next Up

### Requirement: Cached library, refreshed in the background
The film and series lists SHALL be shown from a local cache at launch and refreshed in the
background; watched status and favorites SHALL be refreshed when a Jellyfin section opens.
A server that is not reachable keeps the cached library usable with an amber notice
("Jellyfin nicht erreichbar", the saved library is shown, "Retry"), and the sidebar and the
Home header say "Offline" at the same time.

#### Scenario: Server offline
- **WHEN** the Jellyfin server is not reachable at launch
- **THEN** the cached films and series are shown with a notice that the server is offline
