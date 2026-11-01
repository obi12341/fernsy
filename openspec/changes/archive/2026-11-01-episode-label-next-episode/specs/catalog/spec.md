## MODIFIED Requirements

### Requirement: Watched episodes and the next episode
An IPTV episode played to its end (within its last 90 s) SHALL count as watched and show
"Gesehen" with a check mark. The series detail SHALL offer "Nächste Episode" naming season,
episode and title, chosen by the same rule as on Apple TV and iPhone/iPad: the episode with a
resume position, otherwise the one after the last watched episode (by season and episode number),
the first one when none is watched and the last one when all are; it also carries "Als Nächstes".

#### Scenario: Continuing a series
- **WHEN** episodes 1 and 2 of season 1 were watched to the end
- **THEN** the main action reads "Nächste Episode · S1 F3 · <title>" and episode 3 is labelled "Als Nächstes"

#### Scenario: A skipped episode
- **WHEN** episodes 1 and 3 of season 1 were watched to the end and episode 2 was not
- **THEN** "Nächste Episode" names S1 F4, as on the Apple TV
