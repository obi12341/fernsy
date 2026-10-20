# channel-visibility Specification

## Purpose
Lets the user hide live TV categories and single channels they never watch (other regions,
backup or duplicate feeds), so Live TV only shows what matters to them.

## Requirements

### Requirement: Hide and show from the context menu
Live categories (category column) and live channels (channel list, guide channel column)
SHALL offer "Hide" in their context menu; hidden items offer "Show" in Edit mode.

#### Scenario: Hiding a backup feed
- **WHEN** the user right-clicks "Das Erste HD (Backup)" and chooses Hide
- **THEN** the channel disappears from the list immediately

#### Scenario: Hiding a category
- **WHEN** the user right-clicks the category "UK Sports" and chooses Hide
- **THEN** the category disappears from the category column

### Requirement: Edit mode
Live TV SHALL have an "Edit" toolbar button. In Edit mode, hidden categories and channels are
listed dimmed in their usual place with an eye toggle; every visible item has the toggle too.
"Done" leaves Edit mode. Entering Edit mode while the guide is shown switches to the list.

#### Scenario: Showing a hidden channel again
- **WHEN** the user clicks Edit, then the eye toggle of a dimmed channel, then Done
- **THEN** the channel is listed normally again

#### Scenario: Edit mode in the guide
- **WHEN** the guide is shown and the user clicks Edit
- **THEN** Live TV switches to the list with hidden items visible and dimmed

### Requirement: Edit mode scope
Edit mode SHALL end when the user leaves the Live TV section. While it is active, category
counts SHALL include hidden channels, and the List/Guide switch is unavailable.

#### Scenario: Leaving Live TV
- **WHEN** the user is in Edit mode and opens Movies
- **THEN** Edit mode ends; returning to Live TV shows the normal lists

#### Scenario: Counts while editing
- **WHEN** a category with 4 channels has 1 hidden channel and Edit mode is active
- **THEN** its count shows 4; after Done it shows 3

### Requirement: Channels hidden through their category
A channel that is hidden only because its category is hidden SHALL show a disabled eye
toggle in Edit mode with the hint that its category is hidden; it becomes visible again by
showing the category.

#### Scenario: Channel in a hidden category
- **WHEN** the category "Sports" is hidden and the user looks at its channels in Edit mode
- **THEN** each channel's toggle is disabled with "The category is hidden"

### Requirement: Hidden categories hide their channels
Channels of a hidden category SHALL be treated as hidden everywhere this capability excludes
hidden channels, including the "All" category.

#### Scenario: All channels
- **WHEN** a category with 40 channels is hidden
- **THEN** "All" no longer lists those 40 channels and its count drops by 40

### Requirement: Where hidden channels are excluded
Outside Edit mode, hidden channels SHALL NOT appear in the channel list, the program guide,
Live TV search results or the Favorites section, and category counts SHALL exclude them.

#### Scenario: Searching
- **WHEN** the user searches "Das Erste" and two of its three entries are hidden
- **THEN** only the visible entry is found

#### Scenario: Favorite that is hidden
- **WHEN** a favorite channel is hidden
- **THEN** it no longer appears under Favorites and reappears there when shown again

### Requirement: Zapping skips hidden channels
↑/↓ in the player SHALL skip hidden channels. Zapping away from a hidden channel that is
playing SHALL continue with the neighbouring visible channels.

#### Scenario: Zapping past a backup
- **WHEN** channel 5 is visible, 6 and 7 are hidden and 8 is visible, and the user presses ↓ on channel 5
- **THEN** channel 8 is tuned

### Requirement: Hiding does not stop what runs
Hiding a channel SHALL NOT stop its playback or its recordings.

#### Scenario: Hiding the playing channel
- **WHEN** the user hides the channel that is playing
- **THEN** it keeps playing; it is just no longer listed

### Requirement: Stored per account, ready for sync
Hidden categories and channels SHALL be remembered per provider account across launches and
catalog refreshes, identified by the provider's ids; ids that disappear from the catalog are
ignored, not removed. The stored data SHALL be small and self-contained so it can later be
synced between devices.

#### Scenario: Relaunch
- **WHEN** the user quits and reopens Fernsy
- **THEN** the same categories and channels are hidden

#### Scenario: Other account
- **WHEN** the user signs in with a different provider account
- **THEN** none of the first account's hidden items apply
