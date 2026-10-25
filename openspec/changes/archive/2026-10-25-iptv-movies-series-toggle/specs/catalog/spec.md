## ADDED Requirements

### Requirement: IPTV films and series can be switched off
Settings › Accounts › IPTV SHALL offer the switches "Filme" and "Serien", both on by default.
A switched-off kind SHALL NOT appear in the sidebar, the search or Favorites, and SHALL NOT be
downloaded or kept in the cache. Its favorites, watched marks and resume positions SHALL be
kept. Switching a kind on again SHALL download it right away.

#### Scenario: Jellyfin user switches films off
- **WHEN** the user switches "Filme" off in Settings › Accounts
- **THEN** the Movies section disappears from the sidebar and the next catalog refresh does not download films

#### Scenario: Open section switched off
- **WHEN** the Series section is open and the user switches "Serien" off
- **THEN** the library shows Live TV

#### Scenario: Switched on again
- **WHEN** the user switches "Filme" on again
- **THEN** the films are downloaded, the Movies section returns and earlier film favorites and resume positions are shown again

## MODIFIED Requirements

### Requirement: Library sections and categories
With an IPTV account the sidebar SHALL list Live TV, Movies, Series, Favorites and
Recordings, leaving out Movies or Series while switched off; with a Jellyfin account also the
Jellyfin group. The second column SHALL list the section's categories with item counts, an
"All" entry and a filter field. Recordings SHALL show how many run ("1 läuft"); the sidebar
footer the IPTV server, expiry date and last catalog update.

#### Scenario: Choosing a category
- **WHEN** the user selects a category in the Movies section
- **THEN** only the movies of that category are shown

#### Scenario: Only a Jellyfin account
- **WHEN** the user is signed in to Jellyfin but not to IPTV
- **THEN** the sidebar shows only the Jellyfin group

#### Scenario: Recording in progress
- **WHEN** a recording runs
- **THEN** the Recordings entry in the sidebar shows "1 läuft" in red next to its name

#### Scenario: Series switched off
- **WHEN** "Serien" is switched off in Settings › Accounts
- **THEN** the IPTV group lists Live TV, Movies, Favorites and Recordings
