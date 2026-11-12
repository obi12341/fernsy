# program-guide Specification

## Purpose
A classic TV guide grid for the channels of the selected category: channels as rows, a
horizontal time axis, a now line, and details for each show.

## Requirements

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

### Requirement: Program data loads on demand
Program data SHALL load only for rows that stay visible for a moment, with at most two full
schedule downloads at a time, newest request first; a quick now/next request fills a row
first. Downloads for rows scrolled away SHALL be cancelled.

#### Scenario: Fast scrolling
- **WHEN** the user scrolls quickly through hundreds of channels
- **THEN** only the rows that end up visible are downloaded

### Requirement: Program data is cached
Downloaded schedules SHALL be cached on disk per account and reused until they are older
than 12 hours or reach less than 20 hours ahead (channels without data: retried after one
hour). Entries outside now−3 h … now+4 days are dropped, cache files older than 3 days pruned.

#### Scenario: Reopening the guide
- **WHEN** the guide is opened again after a relaunch within the same day
- **THEN** no schedule is downloaded again for channels already cached

### Requirement: One show at a time per channel
A channel's programme SHALL have at most one show at any time. When the provider's listings
for a channel overlap, Fernsy SHALL keep the largest set of listings that do not overlap and
drop the others; among overlapping listings the one that ends first is kept. The resulting
programme SHALL be the one used wherever shows are read – the guide grid, now and next, search,
the assistant and the MCP tools – on Mac, Apple TV, iPhone and iPad.

#### Scenario: Two versions of the same schedule
- **WHEN** the provider lists "Osasuna - Atlético" from 18:15 to 20:35 and again from 18:25 to
  20:55, and "Top Goals" from 20:35 to 20:45
- **THEN** the channel's row shows "Osasuna - Atlético" once, from 18:15 to 20:35, followed by
  "Top Goals", and no cell lies on top of another

#### Scenario: Placeholder across real shows
- **WHEN** the provider lists a placeholder "Fußball: TBC - TBC" from 09:50 to 12:25 and real
  shows from 09:00 to 10:25, 10:25 to 10:35 and 10:35 to 12:25
- **THEN** the row shows the three real shows and not the placeholder

#### Scenario: The same show listed twice
- **WHEN** the provider lists the same show twice with starts twenty seconds apart
- **THEN** the row and the search results show it once

#### Scenario: Now and next
- **WHEN** the show running now is listed a second time with a start ten minutes later
- **THEN** "next" names the show after the running one, not its second listing

#### Scenario: Programme cached before
- **WHEN** the app opens with a cached programme that still holds overlapping listings
- **THEN** the guide shows it without overlaps, and nothing is downloaded again for that

### Requirement: Small overlaps between consecutive shows
Two listings that overlap by at most two minutes SHALL both be kept as consecutive shows; the
earlier one SHALL end where the later one starts.

#### Scenario: A show that runs a minute into the next
- **WHEN** the provider lists a show from 19:00 to 20:16 and the next one from 20:15 to 21:00
- **THEN** the guide shows both, the first from 19:00 to 20:15 and the second from 20:15 to 21:00

### Requirement: Channels without program data
Rows without program data SHALL show a hatched bar "No program data · the channel plays
anyway · double-click to play" instead of shows; double-clicking it starts the channel.

#### Scenario: Channel without EPG
- **WHEN** the provider returns no listings for a channel
- **THEN** its row shows the hatched bar, and a double-click on it starts the channel

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

### Requirement: Category menu in the guide
While the guide is shown, the category column SHALL give its width to the grid and the
category SHALL be chosen from a menu in the toolbar, with the same entries as the column.

#### Scenario: Switching the category in the guide
- **WHEN** the user picks "Sports" from the guide's category menu
- **THEN** the guide shows the sports channels and the list uses the same category
