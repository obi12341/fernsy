# Design

## Context

- `GuideRow` (FernsyTV/Screens/GuideScreen.swift) draws shows (`ForEach(shows, id: \.start)`)
  and gap bars (`ForEach(gaps, id: \.lowerBound)`). While `entries == nil` the only cell is a
  loading bar over the whole window, id `windowStart`. Each cell is bound to the row's
  `@FocusState focused: Date?` (added for paging back in catch-up).
- When the programme arrives, `entries` goes from nil to a list (first the quick answer, then
  the full table); the loading bar's id disappears and show cells with other ids appear. A
  focused view that disappears leaves tvOS to choose a new focus, often outside the row.

## Goals / Non-Goals

**Goals:**
- Focus stays in its row whenever that row's cells are replaced.

**Non-Goals:**
- Keeping loading rows unfocusable (rejected below); changing how fast programmes load.

## Decisions

1. **Hand focus over on change.** `GuideRow` observes its cells (`onChange` of the ids it
   draws). If `focused` is no longer among them, it sets `focused` to the cell covering a
   reference time: the time now when it lies in the window, else the window's start (the
   window was paged back or forward). That is a show if one covers it, else the gap bar there.
   Done in the same update, so tvOS has no moment without a focused cell in the row. Rejected:
   making the loading bar unfocusable (loading rows could not be reached until they load, which
   tvos-guide-empty-channels set out to fix); giving the loading bar the id of the show that
   will replace it (unknown before the data arrives).

2. **Only for the focused row.** Rows without focus do nothing (`focused == nil`), so redraws of
   other rows never move focus. The row remembers its focused cell only while focus is in it or
   left together with that cell; when focus leaves while the cell is still drawn, the user moved
   it (Down, Left to the rail) and the row forgets it. Rejected: taking focus back when it left
   less than a second before the cells changed; that pulled focus back from the rail, and from
   the next row when the row above finished loading during fast scrolling.

3. **`IPTV_TESTEPGDELAY=<s>`** (debug): `EPGStore` waits that long before applying a channel's
   quick answer and table, so a UI test can press Down through loading rows reliably on the
   fast demo server.

## Risks / Trade-offs

- [The focused cell's id changes for other reasons (paging)] → paging already sets focus itself
  (catch-up); the hand-over then finds `focused` among the cells and does nothing.
- [Focus jumping within the row from the bar's left end to "now"] → the bar spans the window, so
  "now" is where the eye already is in today's window.
