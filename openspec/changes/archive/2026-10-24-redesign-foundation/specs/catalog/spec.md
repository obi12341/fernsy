## MODIFIED Requirements

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
