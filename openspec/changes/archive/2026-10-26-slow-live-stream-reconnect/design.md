# Design

## Context

Live TV and recordings receive a channel through a `LiveTuner`, which runs a headless
`PlaybackSession` over an `HTTPByteSource` and writes into the `TimeshiftBuffer`.
`HTTPByteSource.checkStall()` runs every 0.5 s and reconnects only on silence: no data for
4 s while the player has under 4 s left, 2 s while it has under 1 s, or 30 s regardless (see
`2026-10-24-faster-live-reconnect/design.md`). `lastDataAt` is refreshed by every received
chunk.

The incident behind this change (user's log, 2026-10-25, Sky Sport F1):

| Time | Received | What happened |
|---|---|---|
| until 21:37:41 | 4–17 Mbit/s | normal |
| 21:37:52–21:40:17 | 0.0–1.8 Mbit/s | 10 rebuffers, stalls of 6–30 s, no reconnect |
| 21:40:28 | – | URLSession timeout (12 s silent), reconnect #1 to the same edge (.40) |
| 21:40:34 | – | rejoined with a 101 s gap in the content |
| 21:42:11 | – | the edge closes the connection, reconnect to the same edge gets HTTP 403 |
| 21:42:13 | – | load balancer hands out another edge (.35), stable since |

The first connection's host is not logged; only reconnects are.

## Goals / Non-Goals

**Goals:**
- Replace a trickling connection within about 20 s, while watching live, behind live, or
  only recording.
- Do not go back to the edge that was slow.
- Make the server of every connection visible in the log.
- Tell the user, in the player and in the Recordings section, when the provider's delivery is
  the cause, and only when Fernsy has evidence for it.

**Non-Goals:**
- Changes to the existing silence rules, their thresholds or the attempt limits.
- Slowness detection for the direct-playback fallback (`LiveTuner.State.unsupported`), which
  has no timeshift buffer and therefore no content clock. It keeps the silence rules.

## Decisions

### A. Measure progress on the content timeline, not in bytes

The watchdog compares how much content time arrived with how much wall time passed. The
content time is the buffer time of the newest clock-stream packet the tuner's
`TimeshiftWriter` wrote (`contentTime`, on the continuous buffer timeline the writer already
maintains across jumps and reconnects). The buffer's index (`newest.time`) would also do, but
it only advances at keyframes, which adds up to a GOP of noise to every measurement. The
writer keeps the value behind a lock of its own, so the watchdog never waits for a disk write.

Rejected: a bitrate threshold. Channels range from under 1 Mbit/s (radio, SD) to over
15 Mbit/s (UHD), and bitrate varies within a channel. A fixed or learned byte rate would need
per-channel calibration and misfires on static scenes.

Rejected: the player's distance to the newest data (`reportPlaybackAhead`). It does not exist
for recording-only tuners, and it is huge when the user watches behind live, so a trickle
would never be noticed exactly when a recording is at stake.

### B. Rule: under 9 s of content in the last 15 s

`HTTPByteSource` gets a content-clock closure (`contentClock`), set by the tuner session. Each watchdog tick
samples it, before taking `cond`, into a short ring of `(wall time, content time)` samples.
The ring is cleared when a connection is answered. Once the current connection is at least
20 s old (5 s for the server's replay and first bytes, plus a full 15 s window), the tick
compares the content time now with the sample 15 s ago. Less than 9 s means slow, and the
connection is replaced with the reason "zu langsam: %.0f s Inhalt in 15 s".

Why these numbers: a channel that sends 6 s segments in bursts, on average in real time,
delivers at least 15 − 6 = 9 s in any 15 s window, so it is never judged slow. The
incident's trickle (about 1/5 of real time) falls below 9 s about 10 s after the slowdown,
because the window still holds content from before it.

The content clock is read outside `cond`. `TimeshiftBuffer` has its own lock, and its stats
provider already reads the source's `netStats`, which takes `cond`. Reading inside `cond`
would create a lock-order inversion.

Rejected: a longer window (30 s) to be even safer for burst channels. It doubles the time
until the reconnect, and segmented sources with segments over 6 s are rare among Xtream
live streams (they are continuous TS).

### C. Skip the edge after slow delivery

`HTTPByteSource` remembers `lastSlowAt`. It is set when the slow rule fires, and also on
any tick whose full 15 s window is below the threshold. When an incident starts, `avoidEdge`
is also set if the reason is slowness or `lastSlowAt` is under 60 s old. The first attempt
then goes to the load balancer without the backoff.

This extends decision D of `faster-live-reconnect`. The earlier rule kept "same edge first"
because it keeps timestamps continuous. That still holds for plain drops, which are the
common case and recover in 0.3 s on the same edge. A slow edge has proven to be the problem
itself. In the incident it trickled again and then rejected Fernsy, which cost another
1½ minutes. Landing on another backend is handled by the existing clock alignment
(`ContentHistory`).

Rejected: blacklisting the slow host for the session. The load balancer decides which edge
we get, and edges recover.

### D. Log the server of the first connection

When a live connection's first response arrives, the log gets an info entry
"connected (HTTP 200) via <host>", next to the existing "reconnected … via <host>". The host
is not a credential. The URL path, which carries username and password, is not logged.

### E. Debug switch `trickle`

`IPTV_TESTNET` gets `trickle:<s>`. From second `<s>` on, `HTTPByteSource` throttles the
current connection to `IPTV_TRICKLEKBIT` kbit/s (default 300): received bytes wait in a queue
and are handed on in small portions every 0.1 s, and the task is suspended while the queue
holds more than 256 KB, so the server sees a slow reader too. A reconnect ends the throttling,
which shows the recovery; `IPTV_TRICKLEMORE=<n|all>` keeps it for that many later connections
(a provider without a good server, or a slow line of the user's own), so the player runs dry
and a recording loses content. Dropping bytes would break the TS packets instead.

First tried: suspending the task after each chunk for as long as the chunk takes at the rate.
URLSession hands over chunks of several hundred KB, so at 300 kbit/s the connection went
silent for seconds at a time and the silence rule replaced it first; it never trickled.

`IPTV_TESTCLOCK=1` logs the content clock every 2 s, `IPTV_TESTNOPATH=1` reports no network
path, and `IPTV_SECTION=<section>` opens the library on a section (for screenshots of the
Recordings section).

### F. Provider card only with evidence

`LiveTuner` publishes a connection health derived from the same content clock: `ok`,
`slow`, `silent` (no data for 4 s, the stall rule's timeout), and `reconnecting` with the
target (same edge or load balancer). `PlayerEngine` passes it on for the tuner it plays from.

`slow` means the 15 s window is under 9 s, or a connection answered 10–15 s ago has delivered
under 60 % of the elapsed time, or the last 12 s brought under 5 s. The last rule is for the
card only: a player with a few seconds left runs dry before the 15 s window shows a trickle,
and a channel with 6 s bursts still brings 6 s in any 12 s. It never replaces the connection.

After a reconnect that began while the connection was slow or silent, the health stays
`reconnecting` until the new connection has delivered 5 s in real time (at most 20 s). The
player is still refilling then, and a plain spinner right after the switch would hide what
happened.

Measured on the demo server: a healthy connection delivers 11–14 s per 15 s window (bursts of
2–4 s), so 9 s leaves room. A "silent" threshold of 2 s flipped every 3 s there, between the
bursts.

The status card decides as follows while live playback is buffering after it started:

| Condition | Card |
|---|---|
| macOS network path not satisfied (`NWPathMonitor`) | "Keine Internetverbindung" · "Fernsy spielt weiter, sobald das Netz zurück ist." |
| health `slow`, `silent` or `reconnecting` | "Der Sender kommt zu langsam vom Anbieter" · while reconnecting via the load balancer "Fernsy wechselt zu einem anderen Server des Anbieters …", otherwise "Fernsy wartet auf Daten …" |
| health `ok` | the existing spinner |

Placement: the card sits in the middle of the picture, in place of the spinner, with the same
glass style as the existing "Verbindung wird wiederhergestellt …" card. The picture is frozen
at that moment, so the card covers nothing the user would miss, and it sits where the user is
already looking. It does not take clicks, so double-click for full screen and dragging the
window keep working.

The card appears after 1 s of buffering, so single short stalls stay quiet. The existing
"Verbindung wird wiederhergestellt …" card for the engine's full restarts stays as it is.

The wording says what Fernsy measured: the channel arrives too slowly from the provider. It
does not claim the provider's server is broken, because the user's own line or Wi-Fi can also
be slow while macOS still reports a network. The card does not try to prove more. The only
case it can rule out is no network at all, and that case gets its own card.

Rejected: blaming the provider on every live stall. Stalls with a healthy connection exist
(decoder restarts, a sleeping Mac), and a wrong accusation would cost trust as well.
Rejected: a speed test against another host to tell the user's line from the provider's. It
would cost bandwidth during a stall, and with one stream slot it cannot test the provider.

### G. Note after a successful switch

When a reconnect that targeted the load balancer, after a `slow` or `silent` health, is
followed by 5 s of content in real time, the tuner reports a recovery. `PlayerEngine` raises a
one-shot note for it only when the picture waited while the connection was unhealthy within
the last 60 s: usually the switch happens while the player still has seconds left (the demo
server's 8 s backlog, a provider's replay), and a note about a stall nobody saw would only
confuse. The player
shows it for 5 s as a small glass pill at the top center, below the caption's height and
clear of the recording mark at the top right; the picture is running again, so the middle
stays free: "Ein anderer Server des Anbieters liefert wieder
flüssig." This is the moment Fernsy actually has evidence that the provider's former server
was the problem, so this note can be more direct than the card.

### H. Gaps in recordings

The recorder samples, once per second while a recording writes, the content time the
recording has received and the wall time. Missing content shows up as a growing deficit,
wall time minus content time. The timeline does not carry the hole as a jump, because the
writer starts a new epoch right after the newest time (`timeline jump, new epoch`). Channels
that deliver in bursts make the deficit a saw tooth, so the tracker uses its lower edge over
the last 6 s (the content really missing). When that has grown by 10 s or more since it last
was steady, a gap is opened at the wall time where the growth began. It is closed when the
deficit holds still (within 1 s) for 5 s, and its length is the deficit growth; a recording
that ends during a growth closes it then. Without the smoothing, the demo server's bursts kept
the raw deficit moving by 3–4 s, and a gap only appeared when the recording ended. Gaps are stored as `gaps: [{at, seconds}]` on the `Recording`, an
optional field decoded with a default of `[]`, so existing `recordings.json` files stay
valid. They are saved as they close, so a running recording already lists them.

The row shows a note symbol (not the failure warning) and "Lücke HH:MM (m:ss) – Anbieter hat
zu wenig geliefert", or "N Lücken, insgesamt m:ss – Anbieter hat zu wenig geliefert" with
the single gaps in the help text when there are more than two.

Rejected: marking such a recording as failed. Most of the show is there, and "fehlgeschlagen"
would point at Fernsy again. Rejected: deriving gaps from the log. The log is per run and
redacted, and the recording entry must carry its own history.

### I. When switching does not help

A switch for slowness that is followed, within 2 minutes, by a slow connection again shows
that the server was not the problem: the provider delivers in bursts longer than 6 s, or the
user's own line is slow (macOS still reports a network). Switching every 20 s would then
only add hiccups and, on single-stream accounts, risk 403 answers while the old slot is
released. So the repeat does not switch: it doubles the window (30 s, then 60 s, each needing
60 % of it as content) and judges the current connection again. Only a connection that fails
the longer window is replaced. After 5 minutes without a slow window the rule returns to
15 s. Measured with a permanent trickle on the demo server: switches at 26 s, 91 s and 157 s
instead of every 20 s, playback kept going.

The player card and the recording note keep naming the provider in this case too (the user's
decision: if the cause is unclear, the provider is named rather than Fernsy).

Rejected: stopping switches for good after a repeat. A provider's edge can recover or be
replaced by the load balancer later; one switch a minute keeps that chance at little cost.

### J. Delivery figures in the log

Whenever a live connection that ran 20 s or more ends (replaced or closed), the log gets an
info line, in release builds too: how long it ran, its lowest 15 s window of content, and its
longest pause between received data. The 9 s threshold is based on the demo server (healthy:
11–14 s per window, pauses up to 3.2 s) and one incident. These lines show from real use how
a provider delivers, so the threshold can be tuned with evidence. They contain no host, path
or credentials.

## Risks / Trade-offs

- [A source with segments longer than 6 s gets reconnected every 20 s] → Each reconnect is
  cheap and continues seamlessly. If it shows up in logs, the window can be widened per
  connection after a slow reconnect that brought no improvement. That would be a follow-up
  change.
- [The content clock stalls without the network being slow, e.g. the writer fails] →
  `TimeshiftWriter` failure moves the tuner to `unsupported` and stops the session, so no
  watchdog runs.
- [Going to the load balancer lands on a backend with another clock] → handled by the
  existing alignment, as for every load-balancer reconnect today.
- [Wi-Fi or line problems show the provider card] → the wording only says the channel
  arrives too slowly from the provider, which is what Fernsy observed. The stronger statement
  comes only after another provider server proved to be fine (decision G).
- [The recording gap measurement misreads a channel's clock jump as missing content] → the
  deficit uses the writer's continuous timeline, which already absorbs clock jumps. A
  backwards jump only makes the deficit shrink and never opens a gap.
- [A reconnect far behind the live edge is lined up by content with the wrong loop of a
  looping stream] → seen once on the demo server, which loops the same film: after a long
  trickle the existing content alignment matched identical packets one loop (about 60 s) off,
  and the writer dropped everything as already seen until a later reconnect. Real channels do
  not repeat byte-identical packets; not changed here.
- [A provider that delivers in bursts longer than 6 s gets one needless switch] → the repeat
  rule (decision I) moves it to the 30 s window after the first switch; the log lines
  (decision J) show such providers.
- [A connection at 60–90 % of real time is never replaced] → it delivers 9 s or more per
  window, so the slow rule keeps it, and the player may stall now and then. Catching that would
  need a second rule tied to the player's buffer; left for a follow-up if logs show it.
- [A provider whose single slot is still held by the slow connection answers the load
  balancer with 403] → the existing backoff for load-balancer statuses stays, and the task
  is cancelled before the new request.
