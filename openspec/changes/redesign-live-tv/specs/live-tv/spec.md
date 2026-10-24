## MODIFIED Requirements

### Requirement: Channel list with now and next
The Live TV section SHALL show the channels of the selected category as rows with number,
logo tile, cleaned name with tags, the current show with its progress and the next show's
start and title, and marks for "in the player", "recording", "offline" and favourite.
Selecting a channel SHALL show a detail pane on the right with the channel, "Play", the
favourite toggle, the current show (time, title, progress, remaining minutes, description,
"Record") and the following shows, each with "Record" or "Scheduled". In a narrow window
the pane moves below the list.

#### Scenario: Selecting a channel
- **WHEN** the user selects a channel in the list
- **THEN** the pane on the right shows what is on now with its progress and remaining time, and what follows

#### Scenario: Recording mark in the row
- **WHEN** a channel is being recorded
- **THEN** its row shows "REC" with a red dot and its progress bar is red

#### Scenario: Recording a later show from the pane
- **WHEN** the user clicks "Record" next to the 23:30 show in the pane
- **THEN** the show is scheduled and its button reads "Scheduled"

## ADDED Requirements

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
