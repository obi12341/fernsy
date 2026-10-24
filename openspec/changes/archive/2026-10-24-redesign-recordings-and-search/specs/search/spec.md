## MODIFIED Requirements

### Requirement: Search across all sources
The toolbar search SHALL search all sources at once, whichever section is open: IPTV
channels, films, series and recordings, and Jellyfin films and series. It matches names
anywhere, ignoring case and diacritics, and groups the hits by source in the order channels,
films, series, Jellyfin films, Jellyfin series, recordings, leaving out empty groups and
signed-out accounts. Channel hits show the current show.

#### Scenario: One search, several sources
- **WHEN** the user types "tatort" while Live TV is open
- **THEN** the results show the matching channels, films, series and Jellyfin titles in separate groups

#### Scenario: Clearing the search
- **WHEN** the user clears the search field
- **THEN** the section that was open before is shown again as it was

#### Scenario: Nothing found
- **WHEN** no source has a match
- **THEN** a "no results" message for the query is shown

#### Scenario: Group order
- **WHEN** a search finds a channel, a Jellyfin film and a recording
- **THEN** the channel group comes first, then Jellyfin films, then recordings
