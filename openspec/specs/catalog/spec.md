# catalog Specification

## Purpose
Shows the provider's live channels, movies and series in a three-column library (section,
category, content) with search, favorites and an offline-first cache.

## Requirements

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

### Requirement: Adult categories hidden by default
Categories whose names mark them as adult content SHALL be hidden unless "Show adult
categories" is enabled in Settings. This only hides them; it is no parental lock. Settings ›
Youth protection SHALL list the categories detected as adult content with their names as
delivered.

#### Scenario: Default
- **WHEN** a provider offers a category named like "XXX" or "Adult"
- **THEN** it does not appear until the user enables the setting

#### Scenario: Checking what is hidden
- **WHEN** the user opens Settings › Youth protection
- **THEN** the detected adult categories of live TV, films and series are listed by name

### Requirement: Movies and series browsing
Movies and series SHALL be shown as poster grids with rating, favourite and resume progress
on the poster, sortable by newest, name or rating through a visible segment. The detail view
shows the backdrop under the toolbar without the category column, the runtime as hours and
minutes, "Resume" with position and remaining time, the plot and a details list (director,
cast, genre, format); series show seasons as a segment and their episodes.

#### Scenario: Opening a series
- **WHEN** the user opens a series and picks a season
- **THEN** that season's episodes are listed and can be played

#### Scenario: Film started earlier
- **WHEN** the user stopped a film at 1:12:40 of 2:04:00
- **THEN** its poster shows the progress and the detail offers "Fortsetzen · 1:12:40 · noch 51 Min."

### Requirement: Favorites
Channels, movies and series SHALL be markable as favorites with a star; the Favorites
section groups them by kind. Favorites are stored locally.

#### Scenario: Marking a favorite
- **WHEN** the user stars a channel
- **THEN** it appears under Favorites › Channels, also after a relaunch

### Requirement: Cached catalog, refreshed in the background
The last downloaded catalog SHALL be shown immediately from disk at launch and refreshed
in the background (live channels first); the refresh repeats every 6 hours and on request
(toolbar button, ⌘R).

#### Scenario: Launch with a cached catalog
- **WHEN** the app starts and a catalog of this account is cached
- **THEN** the library is usable before the network refresh completes

### Requirement: Watched episodes and the next episode
An IPTV episode played to its end (within its last 90 s) SHALL count as watched and show
"Gesehen" with a check mark. The series detail SHALL offer "Nächste Episode" naming season,
episode and title: the episode with a resume position, otherwise the first one not watched,
which also carries the label "Als Nächstes".

#### Scenario: Continuing a series
- **WHEN** episodes 1 and 2 of season 1 were watched to the end
- **THEN** the main action reads "Nächste Episode · S1 E3 · <title>" and episode 3 is labelled "Als Nächstes"

### Requirement: Adult channels in Zuletzt gesehen
Settings › Youth protection SHALL offer "Erwachsenen-Sender unter „Zuletzt gesehen“
anzeigen", off by default. While it is off, adult channels (marked as adult by the provider
or in a category detected as adult) SHALL NOT appear in "Zuletzt gesehen", in the list, the
guide or the entry's count. The history keeps them, so turning the setting on shows them
again. The setting is disabled while adult categories are not shown, because adult channels
are hidden everywhere then.

#### Scenario: Default
- **WHEN** adult categories are shown and the user has watched an adult channel and then "Nordlicht 1"
- **THEN** "Zuletzt gesehen" lists "Nordlicht 1" but not the adult channel

#### Scenario: Setting turned on
- **WHEN** the user turns on "Erwachsenen-Sender unter „Zuletzt gesehen“ anzeigen"
- **THEN** the adult channel appears in "Zuletzt gesehen" again, in the order it was watched

#### Scenario: Adult categories hidden
- **WHEN** "Erwachsenen-Kategorien anzeigen" is off
- **THEN** the new setting is disabled and adult channels do not appear in "Zuletzt gesehen"

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
