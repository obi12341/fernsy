## MODIFIED Requirements

### Requirement: Search across all sources
The toolbar search SHALL search all sources at once, whichever section is open: IPTV
channels, live TV shows of the favourite channels, films, series and recordings, and Jellyfin
films and series. It matches names anywhere, ignoring case and diacritics, and groups the hits
by source in the order channels, shows, films, series, Jellyfin films, Jellyfin series,
recordings, leaving out empty groups and signed-out accounts. Channel hits show the current show.

#### Scenario: One search, several sources
- **WHEN** the user types "tatort" while Live TV is open
- **THEN** the results show the matching channels, shows, films, series and Jellyfin titles in separate groups

#### Scenario: Clearing the search
- **WHEN** the user clears the search field
- **THEN** the section that was open before is shown again as it was

#### Scenario: Nothing found
- **WHEN** no source has a match
- **THEN** a "no results" message for the query is shown

#### Scenario: Group order
- **WHEN** a search finds a channel, a show, a Jellyfin film and a recording
- **THEN** the channel group comes first, then shows, then Jellyfin films, then recordings

## ADDED Requirements

### Requirement: Shows of the favourite channels
The search SHALL find shows in the guide of the favourite channels (at most 50) that run now or
later and whose title matches the query. Shows that run now SHALL come first, then by start
time. A hit SHALL show the title, the channel, day and time, whether it runs now, and whether a
recording is planned. Other channels and past shows are not searched.

#### Scenario: A show tonight on a favourite
- **WHEN** "Tatort" airs at 20:15 on the favourite channel "Das Erste" and the user searches "tatort"
- **THEN** the shows group lists "Tatort" with "Das Erste" and today 20:15

#### Scenario: Not a favourite
- **WHEN** the matching show airs only on a channel that is not a favourite
- **THEN** the shows group does not list it

#### Scenario: Running first
- **WHEN** one matching show runs now and another starts later
- **THEN** the running show is listed first and marked as running

#### Scenario: Ended shows
- **WHEN** a matching show on a favourite ended before the search
- **THEN** it is not listed

### Requirement: Guides loaded for the search
When a search starts, the guides of favourite channels that are not loaded yet SHALL be loaded.
Typing SHALL NOT wait for them: the shows group fills in as guides arrive, and a channel whose
guide cannot be loaded is left out without an error.

#### Scenario: Guides arriving
- **WHEN** the user searches right after launch, before the favourites' guides are loaded
- **THEN** the other groups show at once and the shows group appears as soon as the guides have loaded

#### Scenario: Guide not available
- **WHEN** the provider has no guide for one of the favourites
- **THEN** the other favourites' shows are listed and no error is shown

### Requirement: Acting on a show hit
Selecting a show that runs now SHALL play its channel. Selecting a later show SHALL offer to
record it, following the recording rules (padding, stream limit), or say that it is already
planned. The context menu SHALL offer to play the channel, to record or remove the recording,
and to show the channel's guide.

#### Scenario: Playing a running show
- **WHEN** the user selects a show in the results that runs now
- **THEN** its channel starts playing

#### Scenario: Recording a later show
- **WHEN** the user selects a show that starts later and confirms recording
- **THEN** the recording is planned as from the guide and the hit shows it as planned
