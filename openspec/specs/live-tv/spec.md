# live-tv Specification

## Purpose
Lets the user find and watch live channels: channel list with now/next information, starting
a channel and switching channels like on a TV.

## Requirements

### Requirement: Channel list with now and next
The Live TV section SHALL show the channels of the selected category as a list (logo, name,
current show). Selecting a channel SHALL show a panel with the current show (time, progress,
description) and the next two shows.

#### Scenario: Selecting a channel
- **WHEN** the user selects a channel in the list
- **THEN** the panel shows what is on now with its progress and what follows

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
logo, name and current show; tuning waits until key presses stop.

#### Scenario: Pressing ↓ three times quickly
- **WHEN** the user presses ↓ three times within a second
- **THEN** the banner follows each press and only the third channel is tuned

### Requirement: Offline channels
When the provider redirects a channel to its offline placeholder, the player SHALL say that
the channel is currently offline instead of playing the placeholder.

#### Scenario: Offline channel
- **WHEN** the user starts a channel the provider marks offline
- **THEN** the player shows "The channel is currently offline at the provider" and does not retry
