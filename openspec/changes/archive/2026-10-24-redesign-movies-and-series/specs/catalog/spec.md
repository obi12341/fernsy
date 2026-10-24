## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: Watched episodes and the next episode
An IPTV episode played to its end (within its last 90 s) SHALL count as watched and show
"Gesehen" with a check mark. The series detail SHALL offer "Nächste Episode" naming season,
episode and title: the episode with a resume position, otherwise the first one not watched,
which also carries the label "Als Nächstes".

#### Scenario: Continuing a series
- **WHEN** episodes 1 and 2 of season 1 were watched to the end
- **THEN** the main action reads "Nächste Episode · S1 E3 · <title>" and episode 3 is labelled "Als Nächstes"
