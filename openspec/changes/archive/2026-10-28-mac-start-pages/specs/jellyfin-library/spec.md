## MODIFIED Requirements

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

### Requirement: Cached library, refreshed in the background
The film and series lists SHALL be shown from a local cache at launch and refreshed in the
background; watched status and favorites SHALL be refreshed when a Jellyfin section opens.
A server that is not reachable keeps the cached library usable with an amber notice
("Jellyfin nicht erreichbar", the saved library is shown, "Retry"), and the sidebar and the
Übersicht header say "Offline" at the same time.

#### Scenario: Server offline
- **WHEN** the Jellyfin server is not reachable at launch
- **THEN** the cached films and series are shown with a notice that the server is offline

## ADDED Requirements

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

## REMOVED Requirements

### Requirement: Home rows
**Reason**: Replaced by "Jellyfin overview on the Mac", which keeps Continue Watching and
Recently Added and adds the discovery rows; Next Up moves to Start.
**Migration**: None for users; the entry is renamed from Home to Übersicht.
