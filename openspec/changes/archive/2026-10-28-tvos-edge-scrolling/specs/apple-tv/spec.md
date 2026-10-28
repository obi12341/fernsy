## ADDED Requirements

### Requirement: Scrolling content on Apple TV
Poster grids and card rows SHALL never be drawn over a screen's header or view switcher, and
posters SHALL enter and leave at the screen's edge, not vanish at the page margin. A focused
poster SHALL still grow without being cut off.

#### Scenario: Scrolling Jellyfin films
- **WHEN** the user scrolls down the Jellyfin tab's Filme view
- **THEN** the header with the view switcher scrolls away with the posters, and no poster is drawn over it

#### Scenario: Scrolling a row sideways
- **WHEN** the user moves right through a row on Jellyfin's Übersicht or on Start
- **THEN** posters leave at the left screen edge instead of disappearing at the page margin
