# search Specification

## Purpose

One search over everything Fernsy knows locally – live channels, films and series of the IPTV
account, recordings and the Jellyfin libraries – with grouped, ranked results.

## Requirements

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

### Requirement: Ranked and limited results
Within a group, hits whose name starts with the query SHALL come first, then hits where a word
starts with it, then the rest, each alphabetically. Each group SHALL show its first hits and
offer to show all of them.

#### Scenario: Prefix first
- **WHEN** the user searches "sky" and the channels "Sky Sport 1" and "Disney Sky" match
- **THEN** "Sky Sport 1" is listed before "Disney Sky"

#### Scenario: Many hits
- **WHEN** a group has more hits than it shows
- **THEN** it offers to show all, with the total number

### Requirement: Acting on a hit
Selecting a hit SHALL act as in its own section: a channel or recording starts playing, a film
or series of either account opens its detail view.

#### Scenario: Playing a channel from the results
- **WHEN** the user selects a channel in the results
- **THEN** the channel starts playing

#### Scenario: Opening a Jellyfin series
- **WHEN** the user selects a Jellyfin series in the results
- **THEN** its detail with seasons and episodes opens

### Requirement: Same exclusions as the sections
The search SHALL NOT find what the sections hide: hidden channels and categories, adult
categories while they are not enabled in Settings, and the IPTV account's films or series
while they are switched off in Settings › Accounts.

#### Scenario: Adult category
- **WHEN** adult categories are disabled and a film in such a category matches the query
- **THEN** it is not in the results

#### Scenario: IPTV films switched off
- **WHEN** "Filme" is switched off and the user searches for a title that the IPTV provider and Jellyfin both have
- **THEN** only the Jellyfin film is in the results

### Requirement: Search while typing
The search SHALL update the results while the user types, without making typing or scrolling
stutter, for catalogs of at least 50,000 entries.

#### Scenario: Large catalog
- **WHEN** the user types into the search with a catalog of about 50,000 channels, films and series
- **THEN** each keystroke is shown at once and the results follow within a fraction of a second
