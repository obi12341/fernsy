# Proposal

## Why

Provider channel lists are long and noisy: many categories nobody watches (other countries,
sports packages) and several entries per channel (backup feeds, HD/FHD/SD variants). The
user wants to hide categories and single channels in Live TV so lists, guide and zapping
only contain what they actually watch.

## What Changes

- Hide and show live categories and individual live channels (context menu, and an
  "Edit" mode in Live TV that lists hidden items dimmed with a show/hide toggle).
- Hidden categories hide all their channels. Hidden channels disappear from the channel
  list, the program guide, ↑/↓ zapping, Live TV search and Favorites.
- The choice is stored per provider account, in a form that can later be synced across
  devices (e.g. iCloud).

Out of scope: syncing across devices (prepared, not built); automatic detection of
duplicate/backup channels (user decision: manual only); hiding movies or series
categories; reordering or renaming channels; multi-selection bulk hiding.

## Capabilities

### New Capabilities
- `channel-visibility`: hiding and showing live categories and channels, the edit mode, and where hidden items are excluded.

### Modified Capabilities

None (the effects on list, guide, zapping, search and favorites are owned by
`channel-visibility`; existing requirements keep their wording).

## Impact

- `Fernsy/App/AppModel.swift` (visibility store, filtering, zap list, favorites),
  `Fernsy/Views/LibraryView.swift` (category column, Edit button),
  `Fernsy/Views/ChannelListView.swift`, `Fernsy/Views/GuideView.swift`,
  `Fernsy/Views/SeriesViews.swift` (Favorites), `Localizable.xcstrings`.
- New per-account data file next to the catalog cache (Application Support).
