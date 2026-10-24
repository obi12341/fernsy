# Proposal

## Why

The guide grid works but is dense: past, running and recorded shows are hard to tell apart,
and the category column takes width the grid needs. The redesign in the Claude Design project "Fernsy Redesign" (https://claude.ai/design/p/7e8ce8af-3424-46d0-bc65-69847eaa3c9f),
`Programm.dc.html`, distinguishes three cell states through brightness and tint, marks
recordings with a frame and text, and turns the category column into a menu in the title.

## What Changes

- **Cell states**:
  - **Past:** recedes, with dim text.
  - **Running:** violet tint with the elapsed part filled.
  - **Upcoming:** neutral.

  They must also work in light without relying on colour.
- **Recordings**: a red frame plus "● Aufnahme läuft · time"; scheduled ones get a double
  frame plus "● Geplant · time". The selected cell gets an accent ring.
- **Channels without program data**: a hatched row "Keine Programmdaten · Sender läuft
  trotzdem · Doppelklick zum Einschalten".
- **Header**:
  - the category as a title menu ("Deutschland ⌄") with the channel count
  - a list/guide segment
  - a day stepper ("‹ Heute, Mi. 14. Okt. ›")
  - a time-jump menu
  - "Jetzt" in red
  - a search field
- **Time axis**: half-hour ticks, the day change labelled in the axis, and a red now line
  with a time pill.
- **Channel column** (188 pt): logo tile, cleaned name and country tag. Rows are 50 pt.
- **Detail bar** (bottom, 138 pt): logo, "Channel · Today 22:55–23:45 · in 20 Min.", title,
  description, "Aufnehmen R" (or "Aufnahme entfernen") and "Einschalten".
- **Light appearance**: as in the source.

Out of scope:
- Loading or caching of EPG data, which stays as specified.
- Multi-day data beyond what the provider delivers.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `program-guide`: cell states, recording marks, no-data rows (double-click to tune), title
  menu instead of the category column, day and time navigation, and the detail bar layout.

## Impact

- `GuideView.swift` (grid, cells, header, detail bar).
- Depends on `redesign-foundation` and `channel-names-and-countries`.
