## Purpose

Shows the provider's live channels, movies and series in a three-column library (section,
category, content) with search, favorites and an offline-first cache.

## ADDED Requirements

### Requirement: Library sections and categories
The sidebar SHALL list the sections Live TV, Movies, Series and Favorites; the second
column SHALL list the selected section's categories with item counts, an "All" entry and
a filter field.

#### Scenario: Choosing a category
- **WHEN** the user selects a category in the Movies section
- **THEN** only the movies of that category are shown

### Requirement: Adult categories hidden by default
Categories whose names mark them as adult content SHALL be hidden unless "Show adult
categories" is enabled in Settings. This only hides them; it is no parental lock.

#### Scenario: Default
- **WHEN** a provider offers a category named like "XXX" or "Adult"
- **THEN** it does not appear until the user enables the setting

### Requirement: Search per section
The toolbar search SHALL filter the current section by name, ignoring case and diacritics.

#### Scenario: Searching channels
- **WHEN** the user types part of a channel name in Live TV
- **THEN** the list shows only matching channels

### Requirement: Movies and series browsing
Movies and series SHALL be shown as poster grids, sortable by newest, name or rating, with
a detail view (plot, cast, director, rating, backdrop) and, for series, seasons and episodes.

#### Scenario: Opening a series
- **WHEN** the user opens a series and picks a season
- **THEN** that season's episodes are listed and can be played

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
