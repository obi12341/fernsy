## MODIFIED Requirements

### Requirement: Pinned entries in the category column
The Live TV category column SHALL start with "Alle", "Favoriten" (the favourite channels)
and "Zuletzt gesehen" (the last 20 channels played, newest first), followed by the
provider's categories in their delivered order, flat. Hidden channels are left out of the
pinned entries like everywhere else; adult channels are left out of "Zuletzt gesehen" unless
Youth protection allows them there.

#### Scenario: Recently watched
- **WHEN** the user played "Kanal Süd" and then "Nordlicht 1"
- **THEN** "Zuletzt gesehen" lists "Nordlicht 1" first and "Kanal Süd" second

#### Scenario: Favourites in Live TV
- **WHEN** the user selects "Favoriten" in the Live TV category column
- **THEN** only the favourite channels are listed, in the list and in the guide

### Requirement: Channel context menu
A channel's context menu SHALL offer Play, Show in Guide, Add to/Remove from Favourites
(⌘D), Stop Recording (while it is recorded), Remove from "Zuletzt gesehen" (while the
channel is in that history), Hide Channel, Hide Category "<name>" and Channel Info (⌘I); ⌘D
and ⌘I also act on the selected channel.

#### Scenario: Favourite by keyboard
- **WHEN** a channel is selected and the user presses ⌘D
- **THEN** the channel becomes a favourite and shows the star

#### Scenario: Removing a channel from the history
- **WHEN** the user chooses "Aus „Zuletzt gesehen“ entfernen" on "Kanal Süd"
- **THEN** "Kanal Süd" disappears from "Zuletzt gesehen" and stays gone after a restart, while the other entries keep their order

#### Scenario: Channel not in the history
- **WHEN** the user opens the context menu of a channel that was never played
- **THEN** the menu has no entry for "Zuletzt gesehen"
