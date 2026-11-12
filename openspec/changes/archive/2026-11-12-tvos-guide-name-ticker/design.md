# Design

## Context

See proposal.md for the motivation. What shapes the approach:

- A guide row on Apple TV (`GuideRow` in `FernsyTV/Screens/GuideScreen.swift`) is the channel
  column (284 points: logo 116, the name, the archive mark for archive channels) and the cells
  on the time axis. The name is a plain `Text` with `lineLimit(1)`; it is not focusable. Focus
  lives on the cells, and the row already knows which of its cells has it
  (`@FocusState focused: Date?`), so "the row has focus" is `focused != nil`.
- The guide stays open for a long time and has many rows. Rows without focus must not cost
  more than today (ios-guide-performance records how much per-row work costs in a guide).
- The app already has one continuous motion on Apple TV, the Living hero
  (`FernsyTV/Support/LivingBackdrop.swift`): a `TimelineView(.animation(minimumInterval:
  1/30, paused:))` that computes its frame from elapsed time, reports "moving" or "resting" as
  its accessibility value, and is checked by `LivingHeroUITests` with two screenshots. The UI
  tests run with it, so this kind of motion is known to work with XCUITest.
- The demo server's channel 101 is shown as "Northern Light 1" (its "HD" is a quality tag and
  not part of the shown name; an archive channel, so the mark takes room as well); "Current TV"
  (104) fits. No test data has to be added.

## Goals / Non-Goals

**Goals:**

- The full name of the focused row's channel can be read without leaving the guide.
- Rows without focus are built exactly as today: no measuring, no clock.
- The motion can be checked by a UI test and its timing by a unit test.

**Non-Goals:**

- Changing the guide's layout (column width, row height).
- A general marquee for every cut-off text in the app.

## Decisions

### 1. The row's focus drives it

The name moves while any cell of its row has focus (`focused != nil`), shows and bars alike.
That is what "the cursor is in the row" means on Apple TV, where the name itself cannot take
focus.

Rejected: making the name focusable (Left from the first cell would stop on the name before
the rail; one more press on every row for something to read). Rejected: moving the names of
all visible rows (a screen full of moving text, and a clock per row).

### 2. To the end and back, with rests

The motion is a function of the time since the row got focus:

1. rest at the beginning for 1 s;
2. slide left at 40 points per second until the name's end reaches the column's right edge;
3. rest for 1 s;
4. slide back at the same speed;
5. repeat from 1.

The distance is the name's width minus the room it has, so a name that is slightly too long
moves a little and a very long one takes longer, at the same speed. The first rest doubles as
the start delay: pressing Down through the rows quickly starts no motion.

Rejected: an endless loop in one direction (the name leaving on the left and coming back in
from the right, as the system marquee does): the user asked for there and back, and for names
that are a few characters too long, wrapping around shows mostly empty column. Rejected: a
fixed duration per pass instead of a fixed speed (short overflows would crawl, long ones race).

### 3. Shortened at rest, cut at the edge while moving

Without focus the name is today's `Text` with its ellipsis. With focus, and only if the name
is too long, it is drawn at its full width inside the same room, clipped, with a short fade
(about 12 points) at an edge where text continues beyond it. An ellipsis cannot stay while the
text moves, and a hard cut next to the archive mark looks like a rendering fault.

When focus leaves the row, the name is the shortened `Text` again at once, without sliding
back first: the user's eyes are on the next row by then.

Rejected: keeping the ellipsis during the first rest and switching when the motion starts (two
changes of the text instead of one; the ellipsis going away is also the hint that the name is
about to move).

### 4. One small view, used only by the focused row

A new view in `FernsyTV/Support` takes the text, its font and whether it is active:

- not active, Reduce Motion on, or the text fits: the plain `Text` with `lineLimit(1)`;
- otherwise: the full-width text, offset by the motion of decision 2, driven by a
  `TimelineView(.animation(minimumInterval: 1/30, paused: false))` as in the Living hero.

Whether the text fits is measured only while the view is active (its natural width against the
room it gets), so rows without focus do no extra layout. The row passes `focused != nil`.

The motion itself is a pure function in FernsyCore (elapsed time, distance, speed, rest →
offset), next to `GuideGaps` and `GuideWindow`, with unit tests for the rests, both
directions, the loop and a distance of zero.

Rejected:

- *The system marquee* (`UILabel.enablesMarqueeWhenAncestorFocused`). It runs when an ancestor
  of the label has focus; the name is a sibling of the focused cell, not inside it. It also
  loops in one direction (decision 2) and gives no state a test could read.
- *`withAnimation(.linear.repeatForever(autoreverses: true))`.* It has no rests at the ends
  without chaining animations by hand, starts over in ways that are hard to control when the
  text or the room changes, and its position cannot be computed for a test.
- *`keyframeAnimator(repeating:)`.* Less code than a clock and a function, but the timing would
  live in the view only, and the app already has the clock pattern with its tests.

### 5. What tests and VoiceOver see

The name gets the identifier `guide.name.<channel id>`, the full name as its accessibility
label in both states, and the accessibility value "moving" while it slides (else none), as the
Living hero does. Each start writes a detail log line ("guide row 101: name ticker started"),
so a test can tell that moving within the row did not start it over.

Reduce Motion cannot be switched from a UI test, and SwiftUI's environment value for it cannot
be overridden. `IPTV_TESTREDUCEMOTION=1` (debug builds) makes the moving text behave as with
the setting on; it is documented with the other Apple TV switches in DEVELOPMENT.md.

Rejected: writing the simulator's accessibility defaults from the test script (depends on the
simulator's internals and on the script, so the test would not run from Xcode).

## Risks / Trade-offs

- [Focus passes through "none" inside the row] When the window pages by an hour, focus is
  handed back to the cell a moment later, and when a row's programme arrives the focused cell
  is replaced (tvos-guide-focus-while-loading). The name then starts over from its beginning.
  → Accepted for these two cases. Moving between cells of a row must not do that; the UI test
  checks it with the log line of decision 5, and if SwiftUI reports "none" between two cells
  there too, the row keeps the ticker for one run-loop turn before stopping it.
- [A clock at 30 frames per second in the guide] Only one row runs it, and only if its name is
  too long. → The UI test reads the late-frame log (`IPTV_FRAMESTATS=1`) while the name moves
  and attaches it, as `LivingHeroUITests` does; a real Apple TV is the final judge.
- [Reduce Motion users cannot read long names] As today. → Accepted; names on two lines for
  that case would change the row's layout and are out of scope.
- [Text that moves draws the eye] The motion starts after a second, is slow, and only one
  name moves. → Speed and rests are constants in one place if they need tuning after looking
  at it on a television.

## Migration Plan

None. Rollback is reverting the commit.

## Notes from implementing

- **The shown name.** Channel 101 is shown as "Northern Light 1": "HD" is parsed as a quality
  tag and is not part of the name. Beside the archive mark the name has room for about
  "Northern L", so it slides by roughly half its width.
- **The room is the shortened text's own frame.** `TickerText` keeps today's `Text` in the
  layout and hides it while the full text slides in an overlay of the same size, so nothing in
  the row moves when the ticker starts or stops.
- **Focus within the row.** Moving Right to the next cell keeps one "name ticker started" line:
  SwiftUI does not report "none" between two cells of a row, so the run-loop grace from the
  risks was not needed and is not built.
- **Late frames (host simulator, 12 Nov 2026).** Over the same steps (open the guide, focus row
  101, eight screenshots) the app logged 22 late frames in 11 seconds with the name moving and
  31 in 15 seconds with it at rest (`IPTV_TESTREDUCEMOTION=1`). The simulator shows no cost of
  the ticker; a real Apple TV was not measured.
- **The screenshots of 2.4** come from the UI test's attachments, not from a separate launch
  with `IPTV_TAB`/`IPTV_LIVEVIEW`: the remote is needed to put focus into a row.
