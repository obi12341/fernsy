# catch-up Specification

## Purpose

Lets the user watch shows that already ran on channels whose provider keeps an archive, from the
guide on Mac and Apple TV, and shows which channels have one.

## Requirements

### Requirement: Archive channels are marked
Channels whose provider keeps an archive SHALL show a clock symbol next to their name in the
channel list and in the guide's channel column, on Mac and Apple TV. A channel's info SHALL
name the archive's length in days. Only the channel's own archive flag counts; a channel
without it SHALL NOT borrow the archive of another channel with the same programme.

#### Scenario: Channel with a five-day archive
- **WHEN** the provider lists a channel with an archive of 5 days
- **THEN** the channel list and the guide show the clock symbol next to it, and its info reads "Archiv: 5 Tage"

#### Scenario: Sibling channel with an archive
- **WHEN** "Das Erste HDraw" has no archive and "Das Erste HD" with the same programme has one
- **THEN** only "Das Erste HD" is marked, and past shows of "Das Erste HDraw" cannot be played

### Requirement: Playing a past show from the archive
A past show on an archive channel that started within the archive window SHALL be playable from
its start: on Apple TV by clicking it in the guide, on the Mac with "Von vorn ansehen" in the
show's details or by double-clicking it. It SHALL play like a film, with a timeline over the
show, pause and seeking, titled with the show, channel and day. Past shows outside the window
or on other channels SHALL stay dimmed without a play action.

#### Scenario: Yesterday's show
- **WHEN** the user clicks yesterday's 20:15 show on a channel with a 5-day archive
- **THEN** the show plays from its start, and the timeline runs from 20:15 to its end

#### Scenario: Seeking in an archived show
- **WHEN** the user jumps 30 minutes ahead in an archived show
- **THEN** playback continues 30 minutes later in the show

#### Scenario: Older than the archive
- **WHEN** a show ran 6 days ago on a channel with a 5-day archive
- **THEN** it is dimmed and offers nothing to play

### Requirement: Archive playback and the stream limit
An archived show SHALL take one of the account's streams like a live channel: when recordings
hold all of them, the app SHALL ask before stopping one, as when switching channels.

#### Scenario: Single-stream account while recording
- **WHEN** the account allows one stream, a recording runs, and the user starts an archived show
- **THEN** the app asks whether to stop the recording, and plays the show only if the user agrees

### Requirement: Apple TV's guide reaches into the archive
On Apple TV, Left at the guide's earliest window SHALL page further back while the shown
channels have an archive reaching that far (at most 7 days), with the day named above the grid
("Gestern", or the weekday and date); without archive channels it SHALL stop at today's start.

#### Scenario: Paging into yesterday
- **WHEN** the shown channels include one with a 3-day archive and the user pages left past this morning
- **THEN** the grid shows yesterday's evening, titled "Gestern"
