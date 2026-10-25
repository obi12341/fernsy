# Proposal

## Why

"Zuletzt gesehen" lists the last 20 channels played. With adult categories shown, an adult
channel the user watched stays at the top of that list for anyone who opens Live TV. The
only ways to get rid of it today are to turn off adult categories altogether or to play 20
other channels. There is also no way to take a single channel out of the list.

## What Changes

- **A new setting under Settings › Youth protection:** "Erwachsenen-Sender unter „Zuletzt
  gesehen“ anzeigen" ("Show adult channels in Recently Watched"). It is off by default.
  - While it is off, adult channels do not appear in "Zuletzt gesehen": not in the Live TV
    list, the guide or the entry's count.
  - Adult channels count as adult the same way as elsewhere: the provider's `is_adult` flag,
    or a category whose name marks it as adult.
  - The history itself is unchanged. Turning the setting on shows the entries again.
  - The setting only matters while "Erwachsenen-Kategorien anzeigen" is on (otherwise adult
    channels are hidden everywhere anyway). While that is off, the new toggle is disabled.
- **Removing a channel from "Zuletzt gesehen":** a channel that is in the history gets
  "Aus „Zuletzt gesehen“ entfernen" in its context menu (list rows and the detail pane's
  menu). The channel is removed from the stored history at once.

Out of scope:
- clearing the whole list at once;
- a history for films or series (the continue-watching shelf) and the Jellyfin library;
- not recording adult channels at all; the history keeps them, the setting controls whether
  they are shown;
- changes to how adult categories are detected.

## Capabilities

### New Capabilities
- (none)

### Modified Capabilities
- `catalog`: new requirement "Adult channels in Zuletzt gesehen" for the Youth protection
  setting.
- `live-tv`: "Pinned entries in the category column" leaves adult channels out of
  "Zuletzt gesehen" unless the setting is on; "Channel context menu" gets "Aus „Zuletzt
  gesehen“ entfernen".

## Impact

- `Fernsy/App/AppModel.swift`:
  - a published `showAdultInRecent` setting (UserDefaults, default off);
  - `removeRecent(_:)`;
  - an `isAdult(_ channel:)` helper (flag or adult category).
- `Fernsy/Views/ChannelListView.swift`: `filteredChannels` filters the recent entry. The
  guide and the category count use the same function.
- `Fernsy/Views/ChannelDetailPane.swift`: the `ChannelMenu` item.
- `Fernsy/Views/LoginView.swift`: the toggle in `YouthProtectionSettings`.
- `Localizable.xcstrings` (de + en).
