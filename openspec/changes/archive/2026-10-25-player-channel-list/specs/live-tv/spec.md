## ADDED Requirements

### Requirement: Channel list in the player
During live TV the player SHALL open a channel list over the picture with L or a button in
the controls. It lists the zapped category's visible channels in zap order, each with number,
logo, name with tags, current show with progress, and marks for playing, recording and
offline; a menu switches the category. It closes with L, Esc, a click on the picture or after
10 s without interaction.

#### Scenario: Opening the list
- **WHEN** the user presses L while channel 5 of "DE • Sport" plays
- **THEN** a panel with the channels of "DE • Sport" appears at the left, scrolled to channel 5, which is marked as playing

#### Scenario: Other category
- **WHEN** the user picks "Favoriten" in the list's menu
- **THEN** the list shows the favourite channels with what is on now

#### Scenario: Closing without a choice
- **WHEN** the list is open and nothing happens for 10 seconds
- **THEN** it closes and the picture is unchanged

#### Scenario: Films
- **WHEN** a film plays
- **THEN** neither the button nor L opens a channel list

### Requirement: Switching from the player's channel list
Clicking a row, or Return on the highlighted row, SHALL tune that channel like zapping: banner,
and the question when a recording holds the connection. The list stays open. While it is open,
↑/↓ SHALL move the highlight instead of zapping. After the list closes, ↑/↓ zaps through the
tuned channel's own category, as when it is started from the library.

#### Scenario: Browsing with the keyboard
- **WHEN** the list is open and the user presses ↓ twice and then Return
- **THEN** the highlight moves two rows without tuning, and Return tunes that channel while the list stays open

#### Scenario: Zapping after choosing from Favourites
- **WHEN** the user picks a favourite from "DE • Kinder" in the list's "Favoriten" and closes the list
- **THEN** ↓ zaps to the next channel of "DE • Kinder"
