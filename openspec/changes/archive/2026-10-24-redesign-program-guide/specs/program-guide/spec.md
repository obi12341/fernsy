## MODIFIED Requirements

### Requirement: Guide grid
The guide SHALL show 24 hours starting two hours back (on the half hour), with a pinned time
ruler (half-hour marks, day changes), a channel column that stays visible while scrolling
sideways, and a red now line with the current time on the ruler. Past shows recede, the
running show is tinted with its elapsed part filled, upcoming shows are neutral; recorded
and scheduled shows get a red frame (scheduled: double) and the text "Aufnahme läuft" or
"Geplant".

#### Scenario: Opening the guide
- **WHEN** the user opens the guide
- **THEN** the visible time range includes now, and running shows are highlighted

#### Scenario: Scheduled show in the grid
- **WHEN** the user schedules the 23:30 show
- **THEN** its cell gets a double red frame and reads "● Geplant · 23:30–00:15"

### Requirement: Show details
Clicking a show SHALL select it and show a detail bar (channel logo, channel, day, time and
how soon it starts, title, progress if running, description, "Record"/"Remove Recording"
and "Play"); double-clicking a show or a channel starts the channel.

#### Scenario: Selecting a future show
- **WHEN** the user clicks a show starting tonight
- **THEN** the detail bar shows its title, time and description

### Requirement: Channels without program data
Rows without program data SHALL show a hatched bar "No program data · the channel plays
anyway · double-click to play" instead of shows; double-clicking it starts the channel.

#### Scenario: Channel without EPG
- **WHEN** the provider returns no listings for a channel
- **THEN** its row shows the hatched bar, and a double-click on it starts the channel

## ADDED Requirements

### Requirement: Day and time navigation
The guide SHALL offer a day stepper (previous/next day, today first), a menu to jump to a
time of day (now, 06:00, 12:00, 18:00, 20:15, 23:00) and a "Now" button. Days after today
show from midnight; today starts two hours back as before.

#### Scenario: Prime time tomorrow
- **WHEN** the user steps to tomorrow and picks 20:15
- **THEN** the grid shows tomorrow's shows around 20:15

### Requirement: Category menu in the guide
While the guide is shown, the category column SHALL give its width to the grid and the
category SHALL be chosen from a menu in the toolbar, with the same entries as the column.

#### Scenario: Switching the category in the guide
- **WHEN** the user picks "Sports" from the guide's category menu
- **THEN** the guide shows the sports channels and the list uses the same category
