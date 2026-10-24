# Proposal

## Why

A real-world log (about 35 live reconnects in 30 minutes on one provider) shows that the
reconnect itself is fast: the same edge answers HTTP 200 after about 0.3 s. Time is lost
around it:

- **Late detection.** The watchdog waits for 4 s without data even when the player has
  already run dry. About half of the reconnects were logged with "0.0 s buffered", so the
  picture had stood still for up to 4 s before a new connection was even requested.
- **Backoff after a 403.** When the same edge answers 403 (its token expired), the next
  attempt to the load balancer waits through the backoff that is meant for
  single-connection servers. That is 1–2 s extra in 6 incidents.
- **Same edge again.** An edge that stalls right after a reconnect gets picked again for the
  next incident. The log shows chains of stalls exactly 10 s apart.
- **No measurement.** The log does not show how long the picture actually stood, so none of
  this can be measured.

## What Changes

- **A. Measure:** the log records every playback stall with its duration, from buffering
  start to playback resuming. The level is info, or warning from 3 s on.
- **B. Faster detection when the player runs dry:** a second watchdog rule replaces the
  connection after 2 s without data when the player has less than 1 s left. The 4 s / 4 s
  rule and the 30 s rule stay as they are, so channels that deliver in bursts still work.
  The rule only applies while a player reports its buffer; tuners that only record keep the
  old rules.
- **C. 403/401 from the same edge:** go to the load balancer at once, without backoff.
- **D. Avoid a failing edge:** if the same edge stalls again within 20 s after a reconnect
  to it, the next incident starts at the load balancer instead of that edge.
- **Debug switches:** new `IPTV_TESTNET` actions to simulate a 403 from the edge and a
  short-lived connection, so B, C and D can be verified against the demo server.

Out of scope:
- Changing the attempt limit (8), the 6 s "no response" retry or the full-restart logic.
- Prefetching or keeping a second connection (single-stream accounts forbid it).
- Changes to the demo server.
- Film downloads (their continue logic is separate).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playback`: "Seamless live reconnect" gets the faster stall rule, the immediate switch to
  the load balancer after a 403/401 from the edge, and avoiding an edge that failed again
  shortly after a reconnect.
- `app-log`: "Event log" also records playback stalls with their duration.

## Impact

- `Fernsy/Player/HTTPByteSource.swift`: watchdog rule B (with a "player reported recently"
  check), 403/401 handling (C), edge memory (D), and the DEBUG test hooks.
- `Fernsy/Player/PlayerEngine.swift`: stall duration logging (A).
- `openspec/changes/archive/2026-10-20-document-live-dedup/design.md` stays as the record.
  This change's design states which of its decisions it refines.
- README: the new `IPTV_TESTNET` actions.
