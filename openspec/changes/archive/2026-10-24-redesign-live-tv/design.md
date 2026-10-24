# Design

## Context

**Layout today:** `LibraryView` is a three-column `NavigationSplitView`: sidebar,
`CategoryColumn`, then detail. Live TV's detail is `ChannelListView` (list mode) or
`GuideView`.

**Channel list:** rows are `ChannelRow`, with a logo tile, the tagged name (from the
previous changes), a speaker icon while playing, an archive icon and a star button.
`EPGPanel` sits below the list for the selection, showing now and the next two shows with
`RecordButton`. Program data is loaded per channel on demand via
`app.epg.load(id, client:)` / `app.epg.guide(id)`.

**Edit mode:** uses `VisibilityToggle` (an eye button) on rows and categories.

**Loading and errors:** `LibraryView` shows a `ProgressView` overlay while the catalog
loads without cache, and a `ContentUnavailableView` with Retry when it fails without cache.
`app.loadError` and `app.lastUpdated` exist.

**Design source:** Claude Design "Fernsy Redesign", `LiveTV.dc.html`, with the modes
normal, edit, menu, loading, empty and offline. Building blocks come from
`redesign-foundation`: `LogoTile`, `StatusBadge` and `Theme`.

## Goals / Non-Goals

**Goals:**
- Rows that tell what runs now without selecting.
- A detail pane that does not compete with the list's height.
- Edit mode, context menu and states as in the source.

**Non-Goals:**
- The guide grid (`redesign-program-guide`).
- The design's in-content header. The native toolbar keeps the list/guide picker, Edit and
  search, because a second header would duplicate them.

## Decisions

### 1. Detail pane inside `ChannelListView`

`ChannelListView` becomes `HStack { list; Divider; ChannelDetailPane(316 pt) }` when its
width is at least 720 pt. Below that, the pane stays below the list, as today, so narrow
windows keep working. The width is measured with `onGeometryChange`. "Kein Sender
ausgewählt" fills the pane without a selection.

Rejected: a fourth `NavigationSplitView` column. SwiftUI's split view supports three
columns, and the pane belongs to the list's selection, not to the navigation.

### 2. Rows: 58 pt with now and next

`ChannelRow` (also used by search and favourites) gets:
- the number, which is the 1-based position in the shown list, the same number the zap
  banner uses
- the logo tile and the tagged name
- marks via `StatusBadge`: playing, REC, Offline and Ausgeblendet, plus the favourite star
  button
- a second line with the current title and, right-aligned, "Danach HH:MM Title"
- a 3 pt progress bar, red while recording

Each row loads its channel's program with `.task(id: channel.id)` when it appears. The
list is lazy, so only visible rows load, the same way the guide already loads per row.
Rows without data say "Keine Programmdaten", without a bar.

**Offline:** `AppModel.offlineChannels` collects channels whose playback failed with the
provider's offline placeholder during this run. A later successful start removes the
channel again. Fernsy has no other source for this, so the mark only appears after an
attempt.

### 3. Detail pane content

- **Header:** logo tile (80 pt), tagged name, then "Nr. n · Category".
- **Actions:** "Einschalten" (prominent, accent), the favourite toggle, and a "⋯" menu
  with the context menu entries.
- **JETZT card:** the time range, title, progress, "noch N Min.", description, and
  "Aufnehmen" styled in `Theme.record` (the existing `RecordButton` logic).
- **DANACH:** the next up to 4 shows, each with time, title, a short description and a
  capsule button "Aufnehmen" or "Geplant". The capsule is filled red when scheduled and
  toggles like `RecordButton`.

### 4. Context menu and shortcuts

The menu entries, in order: Einschalten, Im Programm zeigen (switches Live TV to the guide;
the category stays), Zu Favoriten hinzufügen / Aus Favoriten entfernen (⌘D), Aufnahme
beenden (only while recording), Sender ausblenden, Kategorie „<name>“ ausblenden, then
Senderinfo … (⌘I).

⌘D and ⌘I act on the selection through hidden buttons, like the ⌘I already added.
"Im Programm zeigen" needs Live TV's mode setter, which is passed in as a closure.

### 5. Edit mode

`VisibilityToggle` becomes a checkbox (`Toggle(.checkbox)`, checked = shown). Hidden rows
are dimmed (opacity 0.42) and show `StatusBadge(.hidden)`. The toolbar shows
"Alle einblenden" (`app.showAll()` clears hidden channels and categories) next to "Fertig".
A note above the list says that hidden channels are left out of the list, guide, search and
zapping. Adult categories, listed only when adult content is allowed, show a
"JUGENDSCHUTZ" tag instead of a checkbox. The column's footer then reads "Erwachsenen-
Kategorien steuerst du in Einstellungen › Jugendschutz."

### 6. States

- **Loading** (no channels yet, `app.isLoading`): 12 placeholder rows plus a card "Sender-
  liste wird geladen …". The design's count ("3.240 von 5.214") is not possible, because
  `get_live_streams` is one response without progress.
- **Empty favourites:** `ContentUnavailableView` with a star, "Noch keine Favoriten", the
  three ways (star, context menu, ⌘D), and "Alle Sender anzeigen", which selects "Alle".
- **Provider unreachable** (`loadError` while channels are shown from the cache): an amber
  banner above the list: "Anbieter nicht erreichbar", "Du siehst die Senderliste vom
  <lastUpdated>", and "Erneut versuchen".

  "Einschalten" stays enabled. The design disables it, but a failed catalog refresh does
  not mean that streams fail; providers often answer the API and streams on different
  hosts.

## Risks / Trade-offs

- **More EPG requests while scrolling.** Every row that appears loads its program. The
  `EPGStore` caches on disk and in memory and coalesces requests, as it already does for
  the guide.
- **`ChannelRow` is shared.** Search and favourites change with it. That is intended:
  `redesign-recordings-and-search` builds on these rows.
