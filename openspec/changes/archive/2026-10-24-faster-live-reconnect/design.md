# Design

## Context

Live connections are watched in `HTTPByteSource.checkStall()` every 0.5 s. Today it
reconnects when no data came for 4 s while the player has less than 4 s left, or after 30 s
regardless. The design behind this is in `2026-10-20-document-live-dedup/design.md`.

- **Why 4 s:** some channels deliver in segment-sized bursts with seconds of silence, so the
  rule is coupled to the player's buffer instead of a fixed idle timeout.
- **Order of attempts:** the first attempt of an incident goes to the same edge host, later
  ones to the load balancer. The delays are 0.2 s, then 0.5 s × attempt.
- **Ending an incident:** it ends with the first 2xx response. Attempts reset after 10 s of
  stable data.

Who reports the buffer: the player reports its distance to the newest data via
`reportPlaybackAhead`. With timeshift (all live TV today) that is the tuner buffer's newest
time minus the play position. A tuner that only records gets no reports, and its
`playbackAhead` stays at the last value (0 when no player ever watched).

Stalls the user sees are `PlaybackSession` `.buffering(true/false)` events after `.started`,
handled in `PlayerEngine.handle`.

The log in question: the same edge answers in about 0.3 s, and about half of the incidents
had "0.0 s buffered" when triggered. A 403 from the edge led to the load balancer after
1.5–3.8 s. Stalls followed each other exactly 10 s apart on the same edge.

## Goals / Non-Goals

**Goals:**
- Shorter visible freezes when the connection stalls.
- No new reconnects for channels that deliver in bursts while the player still has a
  buffer.
- Make freezes measurable in the log.

**Non-Goals:**
- Changing attempt limits, the 6 s "no response" retry, or the engine's full restart.
- A second connection.
- Demo server changes.

## Decisions

### A. Stall duration in the log

`PlayerEngine` notes the time of `.buffering(true)` once `hasStarted` is set. On
`.buffering(false)`, or when another item starts, it logs `AppLog` player
"stalled for X.X s". The level is info below 3 s and warning from 3 s on. The startup
buffering before `.started` is not counted. When the stall ends in a failure or a stop, the
entry says "stalled for X.X s, then …" via the existing failure log, without a separate
entry.

### B. Second watchdog rule: idle > 2 s and ahead < 1 s, only with a fresh report

`checkStall` gets a second condition: `idle > 2 && playbackAhead < 1 && reportAge < 2`.
`reportAge` is the time since the last `reportPlaybackAhead`, stored as
`playbackAheadAt`. The existing rules stay unchanged.

The burst argument from the earlier design is about pauses while the player still has a
buffer. When the player has under 1 s, waiting two more seconds only lengthens a freeze the
user already sees. A burst channel that really runs the player dry is better off with a
reconnect too.

The report-age check keeps recording-only tuners (no player) on the old rules. Their stale
or zero `playbackAhead` would otherwise trigger reconnects every 2 s on burst channels.

Rejected: lowering `stallTimeout` to 2 s overall. That breaks burst channels while the
player still has a buffer, the case the 4 s rule was made for.

A fresh connection is exempt for its first 4 s (`now − connectedAt > stallTimeout`). Without
this exemption, the first demo-server test chained reconnects 2 s apart. A server often fetches
its own buffer before sending the first byte, and the bytes it then replays are duplicates, so
the player does not gain any buffer from them.

Rejected: counting a 0 s buffer immediately as a stall. Single packets arrive late without
the connection being dead, and 2 s of silence is the shortest gap clearly beyond normal
jitter.

### C. 403/401 from the same edge goes straight to the load balancer

In `didReceive response` during a reconnect, a 403 or 401 sets a flag `edgeRejected` for
the current incident. In `liveReconnect`, the next attempt then targets `url` (the load
balancer) with a delay of 0. Other statuses (5xx, 404, 429) keep the backoff, because they
can mean an overloaded or still-occupied slot.

Rejected: dropping the backoff for every non-2xx status. A single-connection server answers
an occupied slot with 403 on some panels as well. But that comes from the load balancer
URL, not from the edge, so the rule only covers the edge response. A 403 from the load
balancer keeps the backoff.

### D. Avoid an edge that failed again shortly after a reconnect

When a reconnect succeeds, `HTTPByteSource` stores `edgeReconnectedAt` and the host it
connected to. If a new incident starts within 20 s of that, on the same host,
`incidentAttempts` starts at "use the load balancer" for this incident. A successful
connection through the load balancer then sets `edgeURL` to the new edge, so later
incidents try that one first.

This refines the earlier decision "first retry on the same edge". The same edge stays the
default, because it keeps timestamps continuous. It is only skipped when it has just proven
unstable. Landing on another backend is handled by the existing clock alignment
(`ContentHistory`).

Rejected: blacklisting the host for the rest of the session. Edges recover, and the load
balancer may hand out the same host again anyway.

### Debug switches

`IPTV_TESTNET` gets two new actions:
- `forbid:<s>`: from second `<s>` on, the next reconnect to the edge is answered as if with
  HTTP 403, once.
- `flaky:<s>`: drops the connection at `<s>` and again 6 s after the reconnect, to trigger D.

Rule B is verified with `stall:<s>` while playing (the player's buffer runs dry), with
`IPTV_LIVELEAD=<s>` (DEBUG) starting live closer to the newest data. With the normal 5 s lead,
the demo server's 3 s chunks never bring the player under 1 s.

## Risks / Trade-offs

- **More reconnects on channels that briefly run the player dry.** Each reconnect is cheap
  (0.3 s) and is only done when the picture is about to stop anyway.
- **Different backends after D.** Their timestamps differ, so the clock is realigned. This is
  existing, tested behaviour (scenario "New connection lands on a backend with another
  clock").
- **Verification against a real provider.** It is only possible when the user's own app is
  closed (single-stream account). The demo server has no edge redirect, so for C and D
  "load balancer" and "edge" are the same URL there. The debug log shows which path was
  taken.
