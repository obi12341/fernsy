# Proposal

## Why

Some providers send several listings for the same time on a channel: a second version of the
same schedule shifted by a few minutes, a placeholder ("Fußball: TBC - TBC") across the real
shows, or the same show twice with starts a few seconds apart. Fernsy only drops listings with
exactly the same start, so the guides draw the rest on top of each other and the titles become
unreadable (reported on iPhone, 2026-11-12; in the Mac app's cache 12 of 118 channels are
affected, mostly sports channels).

## What Changes

- **One show at a time per channel.** When a channel's listings overlap, Fernsy keeps a set of
  listings that do not overlap and drops the others. The set is the largest one that fits (the
  listing that ends first wins), which removes long placeholders and the second version of a
  schedule and keeps the fine-grained programme.
- **Small overlaps are not conflicts.** Two shows that overlap by at most two minutes are both
  kept; the earlier one ends where the later one starts.
- **Everywhere the programme is read.** The rule is applied where listings are cleaned, so the
  guides on Mac, Apple TV, iPhone and iPad, now and next, Start, search, the assistant and the
  MCP tools all see the same programme. Listings already cached are cleaned when they are read;
  nothing has to be downloaded again.
- **Debug switch** to give a demo channel overlapping listings, for tests and for looking at
  the guides.

Out of scope:

- The now line of the iPhone and iPad guide that stands at different times in different rows
  (a display bug, fixed separately on a `fix/` branch without a change).
- The row that shows above the time ruler on a wide iPhone in landscape (seen in the same
  screenshot, cause not looked at yet).
- Telling which of two overlapping listings is the right one. Fernsy cannot know; it picks by
  the rule above and does not merge titles or times of the dropped listings into the kept ones.
- Filling a stretch that only a dropped listing covered. It shows as a stretch without programme
  data, as today for channels with gaps.
- Recordings and server orders that were planned on a listing the rule now drops: they stay
  planned and record as planned, but the guide no longer has a cell to mark for them.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `program-guide`: new requirement that a channel's programme has one show at a time
  (overlapping listings from the provider are resolved before the programme is shown or used).

## Impact

- `Packages/FernsyCore/Sources/FernsyCore/EPGStore.swift`: `clean` (used for the quick now/next
  answer, the full table and the disk cache) gets the rule; the debug switch lives next to
  `IPTV_TESTEPGDELAY`.
- `Packages/FernsyCore/Tests/FernsyCoreTests`: tests for the rule.
- `FernsyiOSUITests`: one test that a row with overlapping listings shows separate cells.
- `DEVELOPMENT.md`: the debug switch.
- No changes to the guides' layout code, the cache format, the demo server or the workers.
