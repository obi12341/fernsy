# Proposal

## Why

IPTV providers name channels and categories with prefixes and decoration, such as
"DE: ZDF HD", "|UK| BBC One FHD" or "########## ADULT ##########". With 50–200 categories
in one list, Live TV is hard to scan. The redesign in the Claude Design project "Fernsy Redesign" (https://claude.ai/design/p/7e8ce8af-3424-46d0-bc65-69847eaa3c9f), under "Sendernamen
bereinigen" and "Live TV · Senderliste", turns prefixes into a country tag and removes the
decoration.

## What Changes

- **Name parser**: a parser for channel and category names. It recognises country prefixes
  in common forms (`DE:`, `|DE|`, `DE -`, `[DE]`, `DE ▎`), quality suffixes (HD, FHD, UHD/4K,
  raw, SD), numbering, and decoration characters (`#`, `=`, `★`, `▎` repeated).
- **Displayed channels**: the cleaned name, a country tag and an optional quality tag. The
  tags stay visible inside a country category, so that duplicates can still be told apart.
- **Raw name**: stays available in a new "Senderinfo …" (⌘I).
- **Category names**: categories are cleaned the same way and show the country as a tag.
  The list stays flat and in the provider's order. Fernsy does not invent levels.
- **Pinned entries**: Alle Sender, Favoriten and a new "Zuletzt gesehen" (the last 20
  channels played) sit at the top.
- **"Kategorien filtern"**: a field above the category column.
- **Everywhere**: the cleaned names are used in the channel list, guide, player, search,
  recordings and the menu bar. File names of new recordings use the cleaned name with the
  country tag.

Out of scope:
- Editing or renaming channels by hand.
- Changing which categories count as adult. Detection stays as it is, only its display
  moves (see `redesign-settings-login-and-menus`).
- Visual styling of the rows (see `redesign-live-tv`).

## Capabilities

### New Capabilities

- `channel-names`: parsing and displaying channel and category names (country tag, quality
  tag, decoration removed, raw name kept).

### Modified Capabilities

- `live-tv`: the category column (still flat) shows cleaned names with country tags, has
  pinned entries including "Zuletzt gesehen", and has a filter field.
- `search`: matches the cleaned and the raw name.
- `recordings`: file names use the cleaned channel name.

## Impact

- New `Fernsy/Xtream/ChannelName.swift` (parser, pure and testable) with a debug
  self-test switch.
- `AppModel`: recently played channels (stored per account like favourites).
- `ChannelListView`, `GuideView`, `PlayerScreen`, `SearchResultsView`, `Recorder`,
  `MenuBar`: display names.
- Edge case: names without a recognisable prefix must stay exactly as they are.
- Not adopted from the design: categories grouped by country with sub-categories
  ("Deutschland › Nachrichten"). Providers deliver flat categories, so the source's levels
  have no counterpart.
