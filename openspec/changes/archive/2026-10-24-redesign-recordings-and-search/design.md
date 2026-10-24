# Design

## Context

**Recordings:** `RecordingsView` lists the sections Läuft, Geplant and Aufgenommen. The
`RecordingRow` shows:
- a status icon and the title
- "channel · time · detail"
- the recording window on its own line
- the error in orange on another line
- a red system `ProgressView` while running

The context menu already offers Finder and Trash. The note that recordings need Fernsy
open appears only in the empty state.

**Search:** `SearchResultsView` already groups by source and uses the redesigned
`ChannelRow` (logo tile, tagged name, now/next) since `redesign-live-tv`. The group order
today is Sender, Filme, Serien, Aufnahmen, Jellyfin-Filme, Jellyfin-Serien.

**Design source:** Claude Design "Fernsy Redesign", `Aufnahmen.dc.html` and `Suche.dc.html`.

## Goals / Non-Goals

**Goals:**
- Outcomes and causes are readable in one place.
- Times sit side by side.
- The search order matches the source.

**Non-Goals:**
- Recording behaviour and search ranking.

## Decisions

### 1. Recording rows

Second line: "channel · Heute 20:15–21:45" and, when padding applies, "· Aufnahme
20:05–21:55" on the same line. A third line appears only for outcomes:

- **Failed:** `exclamationmark.triangle.fill` in `Theme.warning` with "fehlgeschlagen ·
  <cause>".
- **Missed:** `minus.circle` with "verpasst · Fernsy war nicht geöffnet".
- **Skipped:** `minus.circle` with "ausgelassen".
- **Waiting:** "Wartet auf den Sender …" stays as it is.

The size moves into the second line for finished recordings. The running bar becomes the
shared `ProgressBar` in `Theme.record`.

### 2. Footer note

A `safeAreaInset(edge: .bottom)` shows a small info row: "Aufnahmen laufen nur, solange
Fernsy geöffnet ist – auch mit geschlossenen Fenstern über das Menüleistensymbol."

### 3. Search order

The recordings group moves after the Jellyfin groups, matching the source.

## Risks / Trade-offs

- **Long error texts** are cut to two lines; the full text is in the row's help tooltip.
