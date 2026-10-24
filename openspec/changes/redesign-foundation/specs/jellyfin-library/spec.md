## MODIFIED Requirements

### Requirement: Jellyfin group in the sidebar
With a Jellyfin account the sidebar SHALL show a "Jellyfin" group with Home, Films and Series.
Music, live TV and other library types are not shown. The group's header SHALL show the
server's state with a dot and text: the server name while it is reachable, "Offline" while
it is not.

#### Scenario: Server with film, series and music libraries
- **WHEN** the server has libraries of type films, series and music
- **THEN** the group offers Home, Films and Series only

#### Scenario: Server unreachable
- **WHEN** the Jellyfin server cannot be reached
- **THEN** the group header shows an amber dot with "Offline"
