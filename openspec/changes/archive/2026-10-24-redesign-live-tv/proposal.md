# Proposal

## Why

The Live TV list reads like a table, and the now/next panel sits below the list where it
competes for height. The redesign in the Claude Design project "Fernsy Redesign" (https://claude.ai/design/p/7e8ce8af-3424-46d0-bc65-69847eaa3c9f), `LiveTV.dc.html` (modes normal, edit, menu,
loading, empty and offline), gives every row the logo tile, the current show with progress
and "Danach". The detail pane moves to the right, and each state explains itself.

## What Changes

- **Layout**: four columns at 1280 pt: sidebar, categories (224 pt), channel list and a
  detail pane (316 pt) on the right. The detail pane replaces the panel below the list.
- **Channel row** (58 pt):
  - number and logo tile
  - cleaned name with country and quality tags
  - markers: ▶ Im Player, REC, Offline, Ausgeblendet, ★
  - current show, "Danach HH:MM title" and a progress bar (red while recording)
- **Detail pane**:
  - logo, name, tags, number and category
  - "Einschalten", favourite toggle and a ⋯ menu
  - a "JETZT" card with time, title, progress, remaining time, description and "Aufnehmen"
  - a "DANACH" list of following shows, each with "Aufnehmen" or "Geplant"
  - "Kein Sender ausgewählt" when nothing is selected
- **Header**: the title and channel count, a list/guide segment and "Bearbeiten".
- **Edit mode**:
  - checkboxes on categories and channels
  - hidden items stay visible at reduced opacity, labelled "Ausgeblendet"
  - "Alle einblenden" and "Fertig"
  - an explanation that hidden channels are excluded from the list, the guide, search and
    zapping
  - adult categories are locked and point to Einstellungen › Jugendschutz
- **Context menu**: Einschalten ↩, Im Programm zeigen, Favorit ⌘D, Aufnahme beenden R,
  Sender ausblenden, Kategorie „…" ausblenden, Senderinfo … ⌘I. The row gets a focus ring
  while the menu is open.
- **States**:
  - **Loading:** skeleton rows plus a loading card. The design's count ("3.240 von 5.214")
    is not possible, because the provider delivers the channel list in one response.
  - **Empty favourites:** explains the three ways to add one, with "Alle Sender anzeigen".
  - **Provider unreachable:** an amber banner with the timestamp of the cached list and
    "Erneut versuchen". "Einschalten" stays enabled; see the design.
- **Light appearance**: as in the source; logo tiles stay graphite.

Out of scope:
- Name parsing and country tags (see `channel-names-and-countries`). Categories stay flat; the design's country levels are not adopted.
- The guide grid (see `redesign-program-guide`).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `live-tv`: row content, detail pane on the right with recording per show, and the
  loading, empty and offline states.
- `channel-visibility`: edit mode presentation (checkboxes, "Alle einblenden", locked adult
  categories), and context menu entries.
- (⌘D for favourites and the empty favourites state are part of `live-tv`, where they are used.)

## Impact

- `ChannelListView.swift` (rows, detail pane), `LibraryView.swift` (column layout, header,
  states).
- `AppModel`: load progress (channels loaded and total), cached-list timestamp, provider
  reachability.
- Depends on `redesign-foundation` and `channel-names-and-countries`.
