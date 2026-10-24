# live-tv Specification

## Purpose
Lets the user find and watch live channels: channel list with now/next information, starting
a channel and switching channels like on a TV.

## Requirements

### Requirement: Channel list with now and next
The Live TV section SHALL show the channels of the selected category as rows with number,
logo, tagged name, the current show with progress, the next show, and status marks.
Selecting a channel SHALL show a detail pane on the right with "Play", the favourite toggle,
the current show with remaining time and "Record", and the following shows, each with
"Record" or "Scheduled". In a narrow window the pane moves below the list.

#### Scenario: Selecting a channel
- **WHEN** the user selects a channel in the list
- **THEN** the pane on the right shows what is on now with its progress and remaining time, and what follows

#### Scenario: Recording mark in the row
- **WHEN** a channel is being recorded
- **THEN** its row shows "REC" with a red dot and its progress bar is red

#### Scenario: Recording a later show from the pane
- **WHEN** the user clicks "Record" next to the 23:30 show in the pane
- **THEN** the show is scheduled and its button reads "Scheduled"

### Requirement: List or guide view
The toolbar SHALL switch Live TV between "List" and "Guide"; the category applies to both, and
the choice is remembered.

#### Scenario: Switching to the guide
- **WHEN** the user picks "Guide" in the toolbar
- **THEN** the program guide grid of the same channels is shown

### Requirement: Starting a channel
Pressing Play or double-clicking a channel SHALL open the single player window and start
that channel. Only one stream plays at a time.

#### Scenario: Playing a second channel
- **WHEN** a channel is playing and the user starts another one
- **THEN** the player switches to the new channel; the old stream is closed first

### Requirement: Zapping
In the player, ↑/↓ (and Page Up/Down) SHALL switch to the previous/next channel of the
category the channel was started from, wrapping around. A channel banner shows number,
logo, name with tags, the current show with its progress and what follows; tuning waits
until key presses stop.

#### Scenario: Pressing ↓ three times quickly
- **WHEN** the user presses ↓ three times within a second
- **THEN** the banner follows each press and only the third channel is tuned

### Requirement: Offline channels
When the provider redirects a channel to its offline placeholder, the player SHALL say that
the channel is currently offline instead of playing the placeholder.

#### Scenario: Offline channel
- **WHEN** the user starts a channel the provider marks offline
- **THEN** the player shows "The channel is currently offline at the provider" and does not retry

### Requirement: Pinned entries in the category column
The Live TV category column SHALL start with "Alle", "Favoriten" (the favourite channels)
and "Zuletzt gesehen" (the last 20 channels played, newest first), followed by the
provider's categories in their delivered order, flat. Hidden channels are left out of the
pinned entries like everywhere else.

#### Scenario: Recently watched
- **WHEN** the user played "Kanal Süd" and then "Nordlicht 1"
- **THEN** "Zuletzt gesehen" lists "Nordlicht 1" first and "Kanal Süd" second

#### Scenario: Favourites in Live TV
- **WHEN** the user selects "Favoriten" in the Live TV category column
- **THEN** only the favourite channels are listed, in the list and in the guide

### Requirement: Channel context menu
A channel's context menu SHALL offer Play, Show in Guide, Add to/Remove from Favourites
(⌘D), Stop Recording (while it is recorded), Hide Channel, Hide Category "<name>" and
Channel Info (⌘I); ⌘D and ⌘I also act on the selected channel.

#### Scenario: Favourite by keyboard
- **WHEN** a channel is selected and the user presses ⌘D
- **THEN** the channel becomes a favourite and shows the star

### Requirement: Channel list states
While the catalog loads for the first time, the list SHALL show placeholder rows with a
loading note. An empty "Favoriten" entry SHALL explain how to add favourites and offer to
show all channels. When a refresh fails while a cached list is shown, a notice SHALL name
the time of the shown list and offer "Retry".

#### Scenario: Provider unreachable
- **WHEN** the catalog refresh fails and the list from 18:02 is shown
- **THEN** a notice says the provider is not reachable, that the list is from 18:02, and offers "Retry"

#### Scenario: No favourites yet
- **WHEN** the user selects "Favoriten" without any favourite channel
- **THEN** the list explains the star, the context menu and ⌘D, and offers "Show all channels"
