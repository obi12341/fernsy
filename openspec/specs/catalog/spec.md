# catalog Specification

## Purpose
Shows the provider's live channels, movies and series in a three-column library (section,
category, content) with search, favorites and an offline-first cache.

## Requirements

### Requirement: Library sections and categories
With an IPTV account the sidebar SHALL list the sections Live TV, Movies, Series, Favorites
and Recordings; with a Jellyfin account it SHALL also show the Jellyfin group; the second
column SHALL list the selected section's categories with item counts, an "All" entry and
a filter field. The Recordings entry SHALL show how many recordings run ("1 läuft"), and the
sidebar footer SHALL show the IPTV account's server, its expiry date and when the catalog
was last updated.

#### Scenario: Choosing a category
- **WHEN** the user selects a category in the Movies section
- **THEN** only the movies of that category are shown

#### Scenario: Only a Jellyfin account
- **WHEN** the user is signed in to Jellyfin but not to IPTV
- **THEN** the sidebar shows only the Jellyfin group

#### Scenario: Recording in progress
- **WHEN** a recording runs
- **THEN** the Recordings entry in the sidebar shows "1 läuft" in red next to its name

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
