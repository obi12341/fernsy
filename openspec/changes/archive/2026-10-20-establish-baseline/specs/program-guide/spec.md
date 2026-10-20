## Purpose

A classic TV guide grid for the channels of the selected category: channels as rows, a
horizontal time axis, a now line, and details for each show.

## ADDED Requirements

### Requirement: Guide grid
The guide SHALL show 24 hours starting two hours back (on the half hour), with a pinned time
ruler (half-hour marks, day changes), a channel column that stays visible while scrolling
sideways, and a red now line.

#### Scenario: Opening the guide
- **WHEN** the user opens the guide
- **THEN** the visible time range includes now, and running shows are highlighted

### Requirement: Show details
Clicking a show SHALL select it and show a detail bar (channel, time, progress if running,
description, Play); double-clicking a show or a channel starts the channel.

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

### Requirement: Channels without program data
Rows without program data SHALL show a "No program information" bar instead of shows.

#### Scenario: Channel without EPG
- **WHEN** the provider returns no listings for a channel
- **THEN** its row shows "No program information"
