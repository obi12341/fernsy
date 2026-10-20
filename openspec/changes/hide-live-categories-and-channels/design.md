# Design

## Context

Live TV lists come from `AppModel.filteredChannels(categoryID:query:)` (channel list and
guide), zapping from `zapList`/`neighbor`, Favorites from a separate filter in
`SeriesViews.swift`, category counts from `channelsByCategory` in `CategoryColumn`. Each
Xtream live channel has one `categoryId` and a numeric stream id; category ids are
strings. Adult categories are already filtered by `showAdult` (a global setting). Favorites
are stored globally in UserDefaults. See proposal.md for motivation.

## Goals / Non-Goals

**Goals:** one place that decides visibility; storage that a later iCloud sync can take over
unchanged.

**Non-Goals:** the sync itself; duplicate detection; bulk selection.

## Decisions

### One visibility value per account
`ChannelVisibility { version, hiddenCategories: Set<String>, hiddenChannels: Set<Int>,
modifiedAt: Date }`, Codable, stored as `visibility.json` in
`Application Support/Fernsy/<accountKey>/` next to the catalog cache, loaded on sign-in,
cleared from memory on sign-out (file kept).
- Per account because ids are provider-specific (unlike Favorites today, which are global;
  not changed here).
- One small self-contained value with `modifiedAt`: a later sync can store it as one
  `NSUbiquitousKeyValueStore` entry per account (limits 1 MB / 1024 keys are far away;
  ~1000 hidden ids ≈ 10 KB) and merge by set union or last writer.
- Unknown ids are kept, not pruned: a provider temporarily dropping a channel must not
  lose the user's choice, and another device may know ids this one has not loaded.
- Rejected: UserDefaults keys per id – unbounded key count and hard to sync as a unit.
- Rejected: storing channel names – names change and duplicates share them.

### Filtering in AppModel
`isHidden(channel)` = channel id hidden or its category hidden. `filteredChannels` gains
`includeHidden` (Edit mode); `zapList` and the Favorites filter exclude hidden channels;
`neighbor` locates a hidden current channel in the unfiltered list and steps to the next
visible one. Category counts use a visible-count map recomputed when visibility or the
catalog changes (thousands of channels: cheap).

### Edit mode in LibraryView
`@State editingLive` in LibraryView, an "Edit"/"Done" toolbar button in the Live section,
passed to `CategoryColumn` and `ChannelListView`. Entering it switches `liveMode` to list
(the guide stays read-only; hiding from its channel column via context menu still works).
Hidden rows are drawn at reduced opacity with an `eye.slash`/`eye` toggle.

### Adult filter stays separate
Adult categories remain controlled by "Show adult categories"; with that off they stay
invisible in Edit mode too. Hiding is a personal list, not a content lock.

## Risks / Trade-offs

- [User hides everything in a category by accident] → Edit mode shows all hidden items in
  place; nothing is deleted.
- [Provider renumbers stream ids] → hidden channels reappear; acceptable, rare.
- [Playing a hidden channel from Favorites/recordings is no longer possible from lists] →
  showing it again is one click in Edit mode.
