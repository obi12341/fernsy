## MODIFIED Requirements

### Requirement: Day and time navigation
The guide SHALL offer a day stepper (previous/next day, today first), a menu to jump to a
time of day (now, 06:00, 12:00, 18:00, 20:15, 23:00) and a "Now" button. Days after today
show from midnight; today starts two hours back as before. Previous days SHALL be reachable as
far back as the longest archive among the shown channels (at most 7 days) and show from
midnight; without archive channels the stepper starts at today.

#### Scenario: Prime time tomorrow
- **WHEN** the user steps to tomorrow and picks 20:15
- **THEN** the grid shows tomorrow's shows around 20:15

#### Scenario: Back into the archive
- **WHEN** the shown channels include one with a 5-day archive and the user steps back twice
- **THEN** the grid shows the day before yesterday from midnight, and the archive channel's past shows can be played

#### Scenario: No archive channels
- **WHEN** none of the shown channels has an archive
- **THEN** the previous-day button is disabled on today
