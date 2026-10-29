## MODIFIED Requirements

### Requirement: Scrolling content on Apple TV
Poster grids and card rows SHALL never be drawn over a screen's header or view switcher, and
posters SHALL enter and leave at the screen's edge, not vanish at the page margin. A focused
poster SHALL still grow without being cut off. A row with more cards than fit SHALL show the
part of the next card that reaches onto the screen as soon as the row appears.

#### Scenario: Scrolling Jellyfin films
- **WHEN** the user scrolls down the Jellyfin tab's Filme view
- **THEN** the header with the view switcher scrolls away with the posters, and no poster is drawn over it

#### Scenario: Scrolling a row sideways
- **WHEN** the user moves right through a row on Jellyfin's Übersicht or on Start
- **THEN** posters leave at the left screen edge instead of disappearing at the page margin

#### Scenario: The next card at the right edge
- **WHEN** Zuletzt hinzugefügt on Jellyfin's Übersicht has more posters than fit and the page opens
- **THEN** the poster after the last whole one shows at the right screen edge without the row being scrolled first
