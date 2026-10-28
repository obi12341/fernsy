## MODIFIED Requirements

### Requirement: Program guide on Apple TV
Live TV's Programm view SHALL show a guide grid for the chosen source: channels with logo and
name, shows on a time axis with the time now marked, past shows dimmed, running ones
highlighted, recorded or scheduled ones marked. The category column SHALL narrow to a rail that
opens it when clicked. A running show SHALL play the channel when clicked, a later one offer to
record it. Rows without listings, loading, or with gaps SHALL show focusable bars there that
play the channel.

#### Scenario: Playing from the guide
- **WHEN** the user clicks a show that is running now
- **THEN** its channel plays full screen

#### Scenario: Scheduling from the guide
- **WHEN** the user clicks a show that starts later and chooses "Aufnehmen"
- **THEN** the show is scheduled and marked in the grid and in Aufnahmen

#### Scenario: Changing the category in the guide
- **WHEN** the user moves left to the rail, clicks it and clicks "Favoriten"
- **THEN** the column narrows again and the guide shows the favourite channels

#### Scenario: Any category in the guide
- **WHEN** the user opens "Alle Kategorien" from the guide and clicks a category that is not pinned
- **THEN** the guide shows that category's channels

#### Scenario: Channel without listings
- **WHEN** the provider sends no listings for a channel and the user moves down onto its row
- **THEN** the row's bar "Keine Programmdaten" gets focus, and clicking it plays the channel full screen

#### Scenario: Listings ending early
- **WHEN** a channel's listings end at 21:00 and the guide shows 20:00 to 23:00
- **THEN** the stretch from 21:00 is a focusable bar that plays the channel

#### Scenario: Scrolling fast through loading rows
- **WHEN** the user presses Down quickly through rows whose programme is still loading, and it arrives while a row's loading bar has focus
- **THEN** focus moves to that row's show at the same time and stays in the row, the guide does not jump to other rows
