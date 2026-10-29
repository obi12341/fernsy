# Design

## Context

- `HTTPByteSource` suspends its data task when more than `highWater` (24 MB) are buffered ahead
  of the reader (`didReceive`) and resumes it in `resumeIfNeeded()` once less than `lowWater`
  (8 MB) are left. `resumeIfNeeded()` runs on every FFmpeg `read`, so only while the demuxer is
  reading: during playback, not during a user pause once the player's own queues are full.
- The session's `timeoutIntervalForRequest` is `readTimeout` (30 s for non-live). It also runs
  while the task is suspended. A hold longer than that ends in "The request timed out" when the
  task resumes. `continueDownload(at:)` (from `resume-after-dropped-connection`) then opens a
  new connection with `Range: bytes=<end>-`.
- How long a hold lasts is 16 MB divided by the bitrate: about 30 s at 4.3 Mbit/s, so it is
  borderline for SD and archive streams, and harmless for HD films. See proposal.md – Why for
  what the resulting seams do to playback.
- `resume-after-dropped-connection` rejected "closing the connection deliberately after N
  minutes of pause". This change does not touch pauses. It only shortens holds while playback
  consumes data.

## Goals / Non-Goals

**Goals:** a playing download never idles long enough to time out, with the same memory bound.

**Non-Goals:** the user-pause case (unchanged, still handled by continuing the download), seam
verification, and player behaviour at audio gaps (see proposal).

## Decisions

### A: Keep a held download alive every 15 s (half the request timeout), up to a ceiling
Every time `didReceive` holds the task above `highWater`, `HTTPByteSource` schedules a
keep-alive after `readTimeout / 2` (15 s). If the same hold is still in place then (a
generation counter rules out holds that already ended) and less than `keepAliveCeiling`
(2 × `highWater`, 48 MB) is buffered ahead, the task resumes:
- below `highWater` (the reader consumed some), it fills up as usual and is held again at
  `highWater`;
- above it (the reader did not consume: the player's own buffer is ahead, or the user
  pauses), the next delivery holds it again right away, so only what the socket has
  waiting arrives.

The `lowWater` resume in `resumeIfNeeded()` stays. Every hold schedules its own keep-alive,
so the connection never idles 30 s. Memory stays bounded by the ceiling. In a long pause the
ceiling is reached after a few keep-alives. Then the hold may time out, and the existing
continue path takes over when playback resumes, as today.

The first version only resumed after 15 s when the reader had brought the buffer below
`highWater`. The demo test showed a file where the player reads 85 s ahead at the start and
then does not read for about 65 s. That rule left two timeouts in that phase, so it was
replaced by the keep-alive.

- 15 s: half the system timeout (30 s), a quarter of nginx's default `send_timeout` (60 s),
  long enough that bursts stay coarse.
- Ceiling 2 × `highWater`: covers start phases where the player is a minute ahead, while a
  long pause cannot grow the buffer without bound. It also does not reopen the decision in
  `resume-after-dropped-connection`: nothing closes the connection on purpose.
- Rejected: raising `readTimeout` for non-live downloads. The server side (nginx
  `send_timeout`, proxies) still closes a connection that does not read. Dead connections
  would also be noticed later.
- Rejected: dropping the hysteresis and resuming as soon as the buffer falls below `highWater`.
  It works too, but suspends and resumes many times a second, each cycle for a few KB.
- Rejected: resuming early only when the reader consumed (the first version). It misses
  phases without reads, see above.
- Rejected: a bigger in-memory buffer, or downloading whole archives to disk. A bigger
  buffer only makes the hold longer. A full download needs GBs of disk (and tens of GBs for
  Jellyfin 4K), wastes the download when the user stops early, and still needs a cap, and so a
  hold, for large files. Instant seeking back from disk would be a feature of its own.
- Rejected: reconnecting proactively just before the timeout. That still creates a seam,
  which is what produces the audio gaps.

### Finding: our seams are clean, the provider's are not
On the demo test the download timed out every 30 s before the fix, and playback crossed
those seams (at 171 s and 196 s) without drops, rebuffers or an audio dip. Continuing with
`Range` is byte-exact on a static file. The audio gaps in the user's log come from a provider
whose range responses do not continue with the same bytes. Comparing an overlap at the seam
(out of scope here) would detect that.

### B: Water marks for tests
The verification ended up using a local proxy instead: catalog requests go to the demo
server, and films are redirected to the demo's 11-minute `live.ts` (195 MB, 2.37 Mbit/s,
range-capable). That reproduces the user's case with the real marks. The switch stays for
quick runs.

DEBUG builds read `IPTV_TESTWATER=<high KB>:<low KB>[:<timeout s>]` and use those values
instead of 24 MB / 8 MB and the 30 s request timeout. The demo server's film is 14.6 MB and only
52 s long (2.24 Mbit/s), so no hold on it can last 30 s. A short timeout (e.g. 6 s) with small
marks reproduces the timed-out hold before the fix. The hold cap is therefore defined as half
the request timeout (15 s in every normal build), so the same run shows the capped resumes
after the fix. Holds and resumes are logged at detail level (`download held at …` / `resumed after
<s> s`), so the test can read them from the log.

## Risks / Trade-offs

- [More HTTP activity: one resume per 15 s instead of per 30 s] → It is the same connection and
  no new requests are made. TCP flow control does the throttling.
- [A server that closes connections idle for less than 15 s] → Not seen. If it happens, the
  existing continue path still covers it, as it does today.
- [A long pause or a player far ahead beyond the ceiling] → The hold may time out as before.
  The existing continue path covers it, with a seam.
