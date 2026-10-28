## MODIFIED Requirements

### Requirement: Program guide on Apple TV
Live TV's Programm view SHALL show a guide grid for the chosen source: a channel column with
logo and name, the shows on a time axis with the current time marked, past shows dimmed,
running shows highlighted and recorded or scheduled shows marked. The category column SHALL
narrow to a rail with the source's name that opens the column when clicked. Clicking a running
show SHALL play the channel, a later one SHALL offer to record it. Rows without listings, still
loading, or with gaps SHALL show focusable bars there that play the channel when clicked.

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
