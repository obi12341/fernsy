## MODIFIED Requirements

### Requirement: Series page on Apple TV
A series page SHALL show its source, the number of seasons, the description, "Nächste Episode
· S<n> F<n>", the favourite star, a season picker and the season's episodes with number,
runtime, title, watched mark, "Als Nächstes" and progress. For IPTV series the next episode SHALL
be the one with a resume position, else the one after the last watched (the rule the Mac and iOS
apps share). Watched state SHALL come from Jellyfin for Jellyfin series and be kept per account on
the Apple TV for IPTV series.

#### Scenario: Next episode
- **WHEN** the user opens a series whose S2 F3 is watched and S2 F4 is partly watched
- **THEN** the page offers "Nächste Episode · S2 F4", selects Staffel 2 and marks S2 F4 "Als Nächstes"

#### Scenario: All episodes watched
- **WHEN** every episode of an IPTV series is watched
- **THEN** the page offers the last episode as "Nächste Episode"
