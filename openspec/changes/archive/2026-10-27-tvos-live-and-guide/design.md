# Design

## Context

`ChannelListScreen` and `GuideScreen` each hold `@State var source: TVModel.LiveSource?`,
defaulting to Favoriten (or Alle Sender without favourites). The guide picks its source from a
`Menu` with Favoriten, Zuletzt gesehen, Alle Sender and the pinned categories only. In Live TV,
`CategoryColumn` sets the selection in `onChange(of: focused)`, so passing focus over an entry
switches the list. The player zaps through `model.zapSource`, set when a row starts playing.
The Mac (redesign-program-guide) shows the guide inside Live TV and chooses the category once
for both. See proposal.md for the problem.

## Goals / Non-Goals

**Goals:**
- One place for live channels with one source, in two views.
- Every category reachable in both views.
- Choosing a source is a deliberate click.

**Non-Goals:**
- Changes to the guide grid's behaviour or its EPG loading.
- A preview pane in the guide view.

## Decisions

### A. One Live TV tab with a view switch

```
 [Start] [Live TV] [Filme] [Serien] [Aufnahmen]  (search) (gear)

 Liste | Programm                                      <- switch, a focus section
+-----------+---------------------------+------------------+
| Favoriten |  1  Das Erste   Tagesschau|  preview / logo  |
| Zuletzt   |  2  ZDF         heute     |  NOW 20:00-20:15 |
|>Alle   11k|  3  ...                   |  NEXT ...        |
| PINNED    |                           |                  |
| Sport DE  |                           |                  |
| Alle Kat.›|                           |                  |
+-----------+---------------------------+------------------+

 Liste | Programm
+--+-------------+--------------------------------------------+
|A |  Das Erste  | Tagesschau | Wetter | Film: ...              |
|l |  ZDF        | heute      | Krimi ...                      |
|l |  ...        |            |                                |
|e |             |                     now line               |
+--+-------------+--------------------------------------------+
 ^ rail with the source's name; Left from the channel column opens the column over the grid
```

The switch sits above the content as two pill buttons (the design's chip style), in its own
focus section between the tab bar and the content: Up from the first row reaches it, Up again
the tab bar. Clicking a pill changes the view; the source stays.

Rejected:
- **Two tabs sharing one source**: the smallest change, but the guide still has no column,
  and two tabs for one set of channels is what the user finds confusing.
- **The guide's menu with every category**: a menu of 300 entries cannot be used with a remote.
- **Play/Pause toggles the view**: Play/Pause already turns the preview's sound on and off.
- **A row of category chips above both views**: no room for hundreds of categories; the column
  with pinned categories and "Alle Kategorien" already solves choosing.

### B. The column in both views; a rail in Programm

The same `CategoryColumn` serves both. In Programm it collapses to a rail (80 pt) showing
the source's name, so the grid gets the width (as the Mac gives the column's width to the
grid; the axis shrinks from 1440 to 1380 pt for it). Left from the grid reaches the rail;
clicking it opens the column over the grid's left edge with focus on the chosen entry (All
Channels when the source is an unpinned category); clicking an entry sets the source and
collapses it; Right or Back collapses it without a change. Focus returns to the rail. While
the column is open the grid and the switch are disabled, so focus stays in it.

Changed while building: the plan opened the column as soon as focus reached the rail. A
click is used instead: it matches "choosing is a click" (C), and opening on focus made
closing land focus on the rail and open it again. "Alle Kategorien" opens the tiles screen from either view and returns to
the view it came from with the clicked category.

Pitfalls found while building it:
- The switch's focus section must span the screen's width; as wide as its two pills, Down from
  the tab bar went past it into the rows.
- An accessibility identifier on the open column replaced its entries' identifiers; it is a
  container of its own (`accessibilityElement(children: .contain)`).
- The rail's identifier must not start with `guide.`: tests find the grid's cells by that
  prefix.

Also changed while building (seen in screenshots):
- Left at the window's edge paged the guide an hour back and moved focus to the rail in the
  same press. The guide now pages back only to the window it opens with (half an hour before
  now), and the rail is disabled while the window is paged ahead; from the opening window,
  Left goes to the rail. Shows before that window are no longer reachable; on TV they matter
  little (rejected: a separate "earlier" control, more to learn for a rare need).
- The open column dims the grid behind it.
- A category chosen in All Categories and not pinned had no name anywhere in the list view;
  the column now shows it as a selected entry after All Channels (also in the guide's column,
  where focus starts on it).

### C. Select on click

The column's entries set the source in their button action only; `onChange(of: focused)` goes
away. The focused-but-not-chosen entry looks focused, the chosen one keeps the selected look.
This also avoids filtering a large catalog on every focus move.

### D. Source and view in the model, kept per account

`TVModel` gets `liveSource` and `liveView` (Liste/Programm), stored in UserDefaults per account
like the other per-account Apple TV values (tvos-library decision). Both views read them; the
default stays Favoriten, or Alle Sender without favourites. A stored category that no longer
exists or is now hidden falls back to that default. Starting a channel from either view sets
`zapSource` to the source, as rows do today.

### E. Design file

The Claude Design screens (`AppleTV.dc.html`) show Programm as a tab. The user agreed to
deviate from the design here (2026-10-27): the switch and the rail are built from existing
pieces (chip style, column, the design's colours and type sizes) following the sketch above,
and screenshots of both views are compared with the design's Live TV and guide screens for
everything else (rows, pane, grid).

## Risks / Trade-offs

- [Muscle memory: Programm was a tab] → The app is not shipped on Apple TV yet; no migration.
- [Focus between rail and grid] → Pitfalls from tvos-library apply (headers as focus sections);
  UI tests cover Left into the rail, choosing, and Right back to the same show.
- [Switching views with a large source rebuilds the guide] → The guide loads EPG only for
  visible rows already (program-guide spec); the view keeps the focused channel's row in view
  when switching.

## Pitfall found later: the window stood still (2026-10-29)

The guide's window was `@State`, set once when the guide was built. tvOS keeps the app for hours
and Live TV keeps the guide, so a guide opened at 00:43 still showed 00:00–03:00 at 19:27. Its
listings were fresh, but `EPGStore.clean` keeps only three hours back for channels without
archive, so those rows showed only empty bars and the now line was off screen. The window now
follows now (`GuideWindow` in FernsyCore, unit-tested): a window the guide placed itself moves on
once now is within half an hour of its end; any window, paged or not, returns to now after the
guide was out of sight (app in the background, other tab or view) for 30 minutes. A paged window
stays while the user is in the guide.
