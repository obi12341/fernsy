# Design

## Context

Before this change a live channel was a `PlaybackSession` reading straight from
`HTTPByteSource`, with seamless reconnects inside the session (see the baseline design).
Accounts usually allow one stream, and the app is sandboxed. See proposal.md for motivation.

## Goals / Non-Goals

**Goals:** one connection per channel no matter how many consumers; timeshift that survives
reconnects and clock jumps; recordings that are ordinary files.

**Non-Goals:** background recording without the app; waking from sleep (impossible in the
sandbox without a privileged helper); provider catch-up; transcoding.

## Decisions

### Receive into a buffer, always play from the buffer
`LiveTuner` runs a headless `PlaybackSession` (`.tuner` mode: same reconnect, duplicate and
audio-rescue logic, no decoders, no back-pressure) and hands cleaned packets to
`TimeshiftWriter`, which remuxes them with FFmpeg's MPEG-TS muxer into a `TimeshiftBuffer`.
The player is a second session in `.buffer` mode on a `BufferByteSource`. Recordings copy
bytes from the same buffer (`RecordingCopier`).
- Rejected: keep direct live playback and switch to the buffer only on pause/rewind – two
  code paths, a visible switch, and recording-while-watching would still need sharing.
- Rejected: raw TS byte dump of the network stream – reconnect replays and backend clock
  jumps would end up in the buffer and the files.
- Fallback: when the muxer refuses a channel's streams, the tuner reports `.unsupported`,
  releases the connection, and the player plays directly without timeshift.

### Buffer layout
One logical byte stream in segment files (~64 MB) under Caches/Fernsy/timeshift; segments
start at resync points (video keyframes, PAT/PMT re-emitted via `mpegts_flags
+resend_headers`; radio: every second), so the oldest byte and every indexed offset are
valid start points for demuxing and for recordings. In-memory index: buffer time, wall
clock, byte offset per resync point. Trimming keeps segments a reader is in, up to twice the
window. Leftovers are deleted at launch.
- Seeking uses the index and `avio_seek` directly: `av_seek_frame(AVSEEK_FLAG_BYTE)` clamps
  to a file size, which a growing buffer cannot report.
- Positions reported by the buffer session are buffer time (stream time minus the muxer's
  fixed delay of 0.7 s, `ffs_mux_delay()`).

### One continuous timeline (TimeshiftWriter)
The muxer needs strictly increasing timestamps and seeking needs one timeline. Every jump
of the clock stream (video, or audio for radio) – forward > 10 s or backward – starts a new
epoch that continues right after the last written packet; other streams pick the epoch
that places them next to their own last packet (packets still interleaved from before a
jump), and a stream that keeps not fitting gets its own offset. Backward steps are only
treated as replayed duplicates within 15 s after a new connection.
- Bug fixed during rollout: backward jumps were first always treated as replays, so an
  ad splice with an earlier clock discarded ~40 s of video and the player ran dry
  (reproduce with `IPTV_TESTJUMP=25:-40`).

### Live edge
Playback starts 5 s behind the newest data (`PlaybackSession.liveLead`) so bursty
providers do not run dry. "LIVE" is a state (`followsLive`: not paused or rewound since),
not a measured distance – providers delivering in bursts made the measured distance flip
the label constantly. While following live, the timeline is drawn at its end, and the
engine jumps to the edge when it lags > lead + 12 s for 4 s.

### Connections: TunerPool
At most `account.maxConnections` tuners (debug override `IPTV_MAXCONN`), reference-counted
by owner (player, each recording). `blockers(for:as:)` returns what would have to give way.
The player's tuner is released before a new one is acquired (single-connection accounts).
Conflict prompts are sheets (`Prompt.ask`) with a 60 s timeout that favors the scheduled
recording (user decision "ask", recordings were planned for a reason).

### Recordings
`Recorder` (per account, JSON in Application Support) checks every 5 s, tunes 20 s before
the padded start, waits for the start time and the first index entry, then copies from the
last resync point at or before the start. Files go to the real `~/Movies/Fernsy` (entitlement
`com.apple.security.assets.movies.read-write`; the path comes from `getpwuid`, not the
container). `ProcessInfo` activity keeps the Mac from idle sleep during and up to an hour
before recordings; quitting asks via `applicationShouldTerminate`.
- Rejected: user-chosen folder with security-scoped bookmarks – more UI for little gain.
- Rejected: background helper/login item (user decision; App Review risk, still no wake).

### Menu bar
A `MenuBarExtra` with the activation policy switching to `.accessory` when the last window
closes and back to `.regular` when one becomes key.
- Pitfall: `MenuBarExtra(isInserted:)` bound to `@AppStorage` writes the binding back on
  every update and loops forever on the main thread; the binding is read-only.

## Risks / Trade-offs

- [Disk use 2–4 GB/h per buffer] → setting down to 2 minutes; buffer dropped on channel change.
- [Muxer cannot write some codec] → direct playback fallback, recording fails with a message.
- [Mac asleep at recording time] → prevented only by idle-sleep assertion while the app runs;
  closed lids or manual sleep still miss recordings.
- [Movies entitlement questioned in review] → reason: recordings are saved there.
- [MPEG-TS timestamps wrap after 26.5 h] → buffers are at most two hours; very long
  continuous recordings were not tested.
