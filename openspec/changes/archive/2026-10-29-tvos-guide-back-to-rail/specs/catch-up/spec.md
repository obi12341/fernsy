## MODIFIED Requirements

### Requirement: Apple TV's guide reaches into the archive
On Apple TV, Left at the guide's earliest window SHALL page further back while the shown
channels have an archive reaching that far (at most 7 days), with the day named above the grid
("Gestern", or the weekday and date); without archive channels it SHALL stop at today's start.
Back in the grid SHALL return a paged window to the current one, and from the current window
move focus to the rail.

#### Scenario: Paging into yesterday
- **WHEN** the shown channels include one with a 3-day archive and the user pages left past this morning
- **THEN** the grid shows yesterday's evening, titled "Gestern"

#### Scenario: Back to now
- **WHEN** the user has paged back into yesterday and presses Back
- **THEN** the grid shows the current window again (the time now inside it), with focus in the same row

#### Scenario: Back to the rail
- **WHEN** the grid shows the current window, a show has focus and the user presses Back
- **THEN** the rail has focus, and clicking it opens the category column
