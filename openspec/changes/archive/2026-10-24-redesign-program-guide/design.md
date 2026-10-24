# Design

## Context

`GuideView` is a two-axis `ScrollView` with a lazy row stack. The ruler is pinned as a
section header. The channel column stays put through `visualEffect` offsets, so scrolling
does not rebuild views, and rows build only the cells near the visible area (2-hour
chunks).

**Range:** origin is now minus 2 h on the half hour, and the span is 24 h.

**Cells:** a running show gets an accent tint, a past one is dimmed, and recordings show a
small symbol. Rows without data show a plain "Keine Programminformationen" bar.

**Details:** a bar below the grid with the channel, times, title, progress and
description, plus `RecordButton`, Play and Close. The toolbar has a "Jetzt" button.

**Category:** chosen in the `CategoryColumn` (content column of the split view), the same
for list and guide.

**Design source:** Claude Design "Fernsy Redesign", `Programm.dc.html`, dark and light.
Shared parts come from `redesign-foundation` (`LogoTile`, `Theme`) and the tagged names
from `channel-names-and-countries`.

## Goals / Non-Goals

**Goals:**
- Three cell states that read in both appearances.
- Clear recording marks.
- A grid that gets the column's width.
- Day and time navigation.

**Non-Goals:**
- EPG loading and caching, which stay as specified.
- A guide inside the player.
- Changing scroll performance characteristics.

## Decisions

### 1. Cell states drawn in `GuideCell`

The three states:
- **Past:** a faint fill (`.fill.quinary`) and tertiary text.
- **Running:** an accent tint (0.20) with an elapsed overlay (accent 0.18) as wide as
  `(now − start)` and semibold title text.
- **Upcoming:** `.fill.tertiary` and primary text.

Recordings:
- **Running or done:** an inset 1.5 pt stroke in `Theme.record`.
- **Scheduled:** the same stroke plus a second inner stroke (3 pt inset, background
  colour), which reads as a double frame.

The second line then reads "● Aufnahme läuft · HH:MM–HH:MM" or "● Geplant · …" in red,
semibold. Otherwise it shows the time range. Selected cells keep the 2 pt accent ring. The
elapsed overlay is computed from the row's `now`, which the 30 s `TimelineView` already
provides.

### 2. No-data rows

The placeholder becomes a hatched bar: a repeating diagonal stripe pattern drawn with
`Canvas` once per row, plus a thin border. It reads "Keine Programmdaten" with a second
line "Sender läuft trotzdem · Doppelklick zum Einschalten". Its text stays sticky, as it is
today. A double-click on the bar plays the channel.

### 3. Category menu instead of the column

While Live TV shows the guide and Edit mode is off, `LibraryView` collapses the content
column, the same way it already does for Jellyfin Home. `GuideView` gets a toolbar `Menu`
titled with the current category's display name. The menu entries are Alle, Favoriten,
Zuletzt gesehen, a divider, then the visible categories. It writes to the same
`categoryBySection[.live]` binding, so the list and guide share the choice.

Rejected: keeping the column and adding the menu. The point of the change is to give the
grid the width.

### 4. Day stepper and time jumps

`GuideView` keeps a `dayOffset` (0 = today, max 3 because the EPG covers about 4 days).
- **Origin:** today it is the existing two-hours-back origin; for later days it is the
  start of that day.
- **Toolbar:** a control group "‹ Heute, Mi. 14. Okt. ›" steps the day, and a menu jumps
  to a time (Jetzt, 06:00, 12:00, 18:00, 20:15, 23:00). Each jump calls
  `position.scrollTo` on the time's x position in the current origin.
- **Stepping:** keeps the time of day that is currently at the left edge.
- **Jetzt:** in red (`Theme.record`), returns to today and scrolls to now.

### 5. Ruler and detail bar

The now line gets a pill on the ruler with the current time (red, white text).

The channel column grows to 188 pt, as in the source.

The detail bar is laid out as in the source:
- a logo tile (72 pt)
- a caption "Kanal · Heute 22:55–23:45 · in 20 Min." (or "läuft seit 10 Min." / "vorbei")
- the title and description
- on the right, a column with "● Aufnehmen R" (red, or "Aufnahme entfernen" /
  "Aufnahme beenden") and "Einschalten"

"R" becomes a keyboard shortcut for the selected show while the guide has focus. The close
button stays as a small ✕.

## Risks / Trade-offs

- **Hatched rows draw extra.** They are drawn once per visible no-data row with `Canvas`,
  which is cheap.
- **The collapsed column hides the category list.** Edit mode, which needs the column,
  already switches to the list.
