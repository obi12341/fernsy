## MODIFIED Requirements

### Requirement: Where hidden channels are excluded
Outside Edit mode, hidden channels SHALL NOT appear in the channel list, the program guide,
the search results or the Favorites section, and category counts SHALL exclude them. In Edit
mode the search filters the channel list, hidden channels included, so they can be found and
shown again.

#### Scenario: Searching
- **WHEN** the user searches "Das Erste" and two of its three entries are hidden
- **THEN** only the visible entry is found

#### Scenario: Searching in Edit mode
- **WHEN** the user searches "Das Erste" in Live TV's Edit mode
- **THEN** the channel list shows all three entries, the hidden ones marked as hidden

#### Scenario: Favorite that is hidden
- **WHEN** a favorite channel is hidden
- **THEN** it no longer appears under Favorites and reappears there when shown again
