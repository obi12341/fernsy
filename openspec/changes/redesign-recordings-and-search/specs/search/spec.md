## MODIFIED Requirements

### Requirement: Search across all sources
The toolbar search SHALL search all sources at once, whichever section is open: channels,
films, series and recordings of the IPTV account and films and series of the Jellyfin account.
It matches names and titles anywhere, ignoring case and diacritics, and shows the hits grouped
by source in the order channels, films, series, Jellyfin films, Jellyfin series, recordings;
groups without hits and sources of accounts that are not signed in are left out. Channel hits
show the logo, tagged name and current show, so they can be started directly.

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
