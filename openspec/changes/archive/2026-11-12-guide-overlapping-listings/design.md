# Design

## Context

See proposal.md for the motivation. What shapes the approach:

- All platforms read a channel's programme from `EPGStore` (FernsyCore). Listings pass through
  `EPGStore.clean` in three places: the quick now/next answer, the full table, and the disk
  cache when it is read. `clean` sorts by start, drops listings with exactly the same start and
  cuts to the kept range (three hours back, or the archive's days, to four days ahead).
- The guides place each listing by its start and end (`Placement` on iPhone/iPad and Apple TV,
  the row layout on the Mac). Overlapping listings therefore overlap on screen; the cells are
  translucent, so both titles show.
- Other readers assume one show at a time too: `nowAndNext` takes the first listing that has
  started and the first that starts later, which can be two listings of one show.
- Shows are identified by channel and start: `show_id` in the tools, recordings (start within
  60 s and the title), server orders (start within 1 s).
- Measured on the Mac app's guide cache on 2026-11-12 (one provider, 118 channels, 7533
  listings): 12 channels with 80 overlapping neighbours. Three patterns: a second version of the
  schedule shifted by 5 to 15 minutes, placeholders across real shows, the same show with starts
  seconds or a few minutes apart.

## Goals / Non-Goals

**Goals:**

- One place that resolves overlaps, so every reader on every platform gets the same programme.
- Kept listings stay what the provider sent (id, title, start), so everything that identifies a
  show by channel and start keeps working.
- No download and no cache format change: cached programmes are resolved when read.

**Non-Goals:**

- Guessing which listing is true, merging listings, or repairing the provider's times.
- Changing the guides' layout code.

## Decisions

### 1. Resolve in `EPGStore.clean`, not in the guides

The rule becomes part of `clean`, which already is the single step between the provider's
answer (or the cache) and everything that reads listings.

Rejected: handle overlaps in each guide's layout (lanes within a row, or drawing only the top
cell). It would be three implementations, would leave now/next, Start, search and the tools
with overlapping listings, and lanes would make rows of affected channels taller than the rest.

### 2. The rule: earliest end first

Listings are taken in the order of their end (equal ends: earlier start first); a listing is
kept when it starts at or after the end of the last kept one. This is the classic selection of
the largest set of intervals that do not overlap. The result is returned sorted by start.

Compared on the 12 affected channels of the cache:

| Rule | Overlaps left | Listings dropped | Time left uncovered | Side effects |
|---|---|---|---|---|
| Each listing ends where the next starts | 0 | 0 | 0 | 61 shows cut by more than 10 minutes, 21 new cells under 10 minutes |
| Earliest end first (chosen) | 0 | 46 | 0 | none |
| Same title only once, then earliest end first | 0 | 49 | 695 minutes | gaps |

Rejected:

- *Each listing ends where the next starts.* Keeps everything, but a placeholder cuts the real
  show before it short, and the two versions of a schedule turn into alternating slivers with
  the same title.
- *Same title only once first.* Keeping the first of two same-titled listings keeps the one that
  ends later about as often as not, which then loses against its neighbours and leaves gaps.
- *Largest covered time* (weighted selection by duration). Not measured; by construction it
  prefers one long placeholder over the short real shows under it, which is the wrong way round
  for the placeholder pattern.

The rule replaces the "same start only once" step: listings with the same start overlap, so one
of them is kept anyway.

### 3. Two minutes of overlap are not a conflict

A listing that starts up to two minutes before the last kept one ends (and after it starts) is
kept, and the kept one's end is moved to that start. On the cache the result is the same with
0, 2 and 5 minutes; the tolerance is there for providers whose consecutive shows overlap by a
minute, where dropping would remove a whole show and leave a gap in its place.

Rejected: no tolerance (see above), and a larger one (5 minutes or more), which would start to
keep both versions of a schedule shifted by five minutes as alternating shows.

### 4. Resolve before cutting to the kept range

Overlaps are resolved on the whole list and the result is then cut to the kept range. Resolving
after the cut would let the selection flip while time passes: once the listing that won an
overlap leaves the range, the one that lost would come back. A programme read from the cache is
already resolved, and resolving it again changes nothing (covered by a test).

Accepted: the quick now/next answer holds only the next ten listings and is resolved on its
own, so a row can change slightly when the full table arrives a moment later, as it already can
today.

### 5. Kept listings are not rewritten

A kept listing keeps its id, title, description and start; only its end can move, and only in
the two-minute case. Titles or times of dropped listings are not merged in.

Rejected: mark the kept listing for a recording or server order that was planned on a dropped
one (matching by overlap instead of by start). The matching by start and title is deliberate
elsewhere, such plans are few and run out within days, and they still record and still show in
Recordings.

### 6. Debug switch and log

`IPTV_TESTEPGOVERLAP=<channel id>` (debug builds) adds overlapping listings to that channel's
downloaded programme before it is cleaned – a second version of each listing ten minutes later
and a placeholder across the shows around now – and skips the disk cache for it, like
`IPTV_TESTEPGDELAY`. The demo server's schedules stay as they are. The existing detail log line
for a downloaded table also says how many listings were dropped for overlapping, which is what
the UI test waits for and what a user's log shows when a guide looks thin.

Rejected: overlapping listings in the demo server. Every test and every screenshot of the demo
guide would then depend on the rule, and the worker would have to be deployed for a test input.

## Risks / Trade-offs

- [The kept version is the shorter one] Of two versions of a live match the one that ends
  first is kept, so a recording planned from the guide ends at the earlier time plus the
  padding. → Accepted: before this change the two could not be told apart in the guide either;
  the padding and extending a running recording remain.
- [Short bogus listings inside a long real show] The rule would keep the short ones and drop
  the long show, leaving stretches without programme data. → Not seen in the measured data; the
  log line names how many listings were dropped per channel, and the rule sits in one function
  if a provider needs something else.
- [A stretch only a dropped listing covered] It shows as "no programme data". → Accepted; none
  in the measured data (0 minutes uncovered).
- [Measured on one provider] → The unit tests fix the three patterns; a test that runs the rule
  over a sample directory (`FERNSY_EPG_SAMPLE`, skipped when unset) makes it cheap to check
  another provider's listings later.

## Migration Plan

None. The cache keeps its format; cached programmes are resolved when read and written back
resolved with the next download. Rollback is reverting the commit.

## Notes from implementing

- **The rule on real listings (12 Nov 2026).** `EPGOverlapTests.sampleDirectoryHasNoOverlapsLeft`
  over a copy of the Mac app's guide cache (118 channels, 7533 listings, 12 channels with
  overlaps): no overlaps left, 46 listings dropped, 1 minute left uncovered in total. The minute
  comes from the two-minute tolerance (a kept show is shortened for a sliver that ends before
  the old end); without tolerance it is 0, as in the exploration.
- **Log.** The count in "… overlapping dropped" is the table's listings with a length minus the
  kept ones, before the cut to the kept range.
- **`nowAndNext`** got a static form that takes a list, for the test; the store's method calls it.
- **Tests in the VM.** `GuideEmptyChannelsUITests` (Apple TV) plays a channel at its end and fails
  there in the VM (no video decoding); it passes on the host. The iPad's
  `testGuideScrollsSmoothly` fails in the VM on its late-frame limit (6 per second) with this
  branch and without it: 6.4 to 8.5 late frames per second in four runs of the code before, 6.8
  to 7.0 in three runs with the guide's minute clock (the now-line fix made at the same time,
  `fix/guide-now-line`); rows built were the same (57 to 60). The VM cannot judge the guide's
  smoothness; that check belongs on a real iPad.
- **Seen on the way, not changed.** On Apple TV the elapsed part of a running show's cell does
  not end at the now line when the show began before the window (the cell is cut to the window,
  the fill is a share of the cut width). On iPhone and iPad the title of a show that began left
  of the visible hours is out of sight (the Mac moves it into view).
