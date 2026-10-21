# Design

## Context

- Live TV plays from the tuner's timeshift buffer. A new session starts at
  `newest - PlaybackSession.liveLead` (5 s) as soon as the first data is buffered (startup
  ~0.5 s).
- "LIVE" is a state (`progress.followsLive`), not a measured distance (decision in
  `add-timeshift-and-recordings`, "Live edge"). `PlayerEngine.catchUpIfLagging` jumps to the
  edge (`goLive`) when `liveEnd - position > liveLead + 12` for 4 s while following live.
- Providers send their stored last seconds as a burst on connect. The user's provider spreads
  ~18 s over the first few seconds; the demo server sends ~3.3 MB (~10 s) instantly and then
  ~0.3 MB/s, so with the demo the burst is complete before playback starts and no jump happens.

## Goals / Non-Goals

**Goals:** no automatic jump at all; "LIVE" during the initial backlog; real lag (stalls) shown
as time behind instead of being corrected by a jump.

**Non-Goals:** changing the start lead, timeshift length or the playback rate.

## Decisions

### Leave live instead of jumping, relative to the settled distance
`catchUpIfLagging` becomes `leaveLiveIfLagging`: it never seeks. Providers deliver in segments,
so `liveEnd - position` swings by several seconds (7–12 s on the demo server); the engine uses
the lowest value of the last 6 s as the steady lag (a peak-based check never stayed above the
threshold for 4 s after a real stall). It keeps a `lagBaseline` per tune: `nil` when a live
load starts; during the first 15 s after `.started` it tracks the largest steady lag (the burst
landing) and nothing happens. After that window the baseline is fixed; when the steady lag
exceeds `max(baseline, liveLead) + 12`,
`progress.followsLive` becomes false – the badge shows the time behind (clickable "Live") and
playback continues. `goLive()` (the user's "Live") resets the baseline to `liveLead`, since
playback is then at the real edge. Reconnects of the tuner do not reset it.
- Rejected: jumping to the edge automatically (today's catch-up) – the user does not want
  playback to jump on its own; being behind is shown instead.
- Rejected: playing faster (e.g. 1.1× with pitch correction) until close to live – the user
  preferred staying behind; a changed speed is audible on music and speech.
- Rejected: waiting for the burst to end before starting – channel switches would take seconds
  longer with this provider.
- Rejected: staying "LIVE" whatever the lag – after stalls the badge would claim live while
  playback drifts ever further behind.

### "LIVE" while behind
Unchanged mechanism: `followsLive` stays true after the start; `behindLive` reads 0 while
following live, so the badge says "LIVE" and the timeline stays pinned at its end even ~20 s
behind the newest data.

### Testing
The demo server's backlog (~10 s) is too short to have produced the old jump, even with a
throttled connection (tried and removed). Debug-only `IPTV_TESTSTALL=<at s>:<s>` holds the
playback clock for that long without touching the live state, which produces lag on demand:
inside the first 15 s it is taken as the settled distance, later it ends the live state. The
user's own provider is used only with their app closed and their OK: on ProSieben HD playback
settled 14.5 s behind the newest data (the backlog) and stayed "LIVE" without a jump.

## Risks / Trade-offs

- [Playback stays ~15–20 s behind the provider's live edge on such channels] → accepted by the
  user; the "Live" action still reaches the real edge.
- [A stall during the first 15 s is taken as burst] → the baseline only raises the threshold for
  leaving live; a further 12 s of lag still ends the live state.
