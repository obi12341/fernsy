# Proposal

## Why

In the Apple TV guide the channel column leaves about 150 points for a channel's name next to
its logo, so longer names are cut off with an ellipsis ("Northern Li…"). That is fine for
scanning the grid, but there is no way to read the full name: the guide has no detail pane for
the channel, and several channels of a provider often differ only at the end of the name
("… 1", "… 2", "… Business").

## What Changes

- **The focused row's name moves.** While focus is on a cell of a channel's row and the
  channel's name does not fit its column, the name slides like a news ticker to its end and
  back, in a loop, with a short rest at both ends, so the whole name can be read.
- **Everything else stays shortened.** Rows without focus show the name cut off with an
  ellipsis as today, and a row goes back to that as soon as focus leaves it. Names that fit do
  not move.
- **Reduce Motion.** With the system setting on, names stay shortened and do not move.

Out of scope:

- Show titles in the guide's cells. They are cut off too when a show is short; the focused cell
  already shows more (its time span), and a moving title inside the focused cell is a different
  question.
- Channel names elsewhere on Apple TV (the channel list, Start, the player's channel strip) and
  the guides on Mac, iPhone and iPad. The moving text is built so that it can be used there
  later, but this change only uses it in the Apple TV guide.
- A wider channel column or names on two lines. The column's width and the rows' height stay
  as they are.
- The system's own marquee for focused labels (see design.md for why it does not fit here).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: a new requirement for channel names that do not fit the guide's channel column
  (shortened at rest, sliding to the end and back while the row has focus).

## Impact

- `FernsyTV/Screens/GuideScreen.swift`: the channel name of a guide row.
- `FernsyTV/Support/`: a new view for text that slides while it is active.
- `Packages/FernsyCore`: the motion over time as a small function with unit tests.
- `FernsyTVUITests`: a new UI test for the guide on the demo server (its channel 101, shown
  as "Northern Light 1", is long enough).
- No new strings, settings, entitlements or dependencies. Mac, iPhone and iPad are not touched.
