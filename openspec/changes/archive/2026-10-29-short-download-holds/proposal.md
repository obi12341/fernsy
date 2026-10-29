# Proposal

## Why

Fernsy holds a film or archive download (task suspended) once 24 MB are buffered ahead and
resumes it at 8 MB. At low bitrates (a ZDF archive at ~4.3 Mbit/s) draining those 16 MB takes
about 30 s, which equals the download's idle timeout. Every hold then ends in "The request
timed out", and the download continues on a new connection. The log of 2026-10-29 shows this
every 2–3 minutes. About 38 s later, when playback reaches the byte where the new connection
starts, audio gaps and dropped frames appear. The player counts them as bursts of 0.0 s
"rebuffers" (60 in 25 minutes), although both buffers are full.

## What Changes

- A held download gets a keep-alive every 15 s: it runs again briefly (fills up if the
  player consumed some, otherwise takes only what the socket has waiting and holds again).
  The connection never sits idle long enough for the system (30 s) or a server (nginx's
  `send_timeout`, 60 s by default) to close it. Memory stays bounded: keep-alives stop at
  48 MB buffered ahead.
- A long user pause reaches that ceiling, and from there on behaves as today. It may time out
  and then continues the download when playback resumes.
- A DEBUG switch scales the water marks down, so the demo server's small film (14.6 MB) can
  exercise holds.

Out of scope:
- Checking the seam of a continued download against the buffered bytes (point 2 of the
  exploration).
- Keeping the picture running through an audio gap in on-demand playback, and counting a burst
  of zero-length stalls as one rebuffer (point 3).
- Downloading whole archives or films to disk.
- Making the buffer chart smoother (net seconds converted at a jumpy bitrate, the needle at a
  reconnect).
- Live TV, which never fills the buffer to the high-water mark at real-time pace and keeps its
  own reconnect path.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `playback`: "Dropped connections do not end on-demand playback" gains the rule that steady
  playback does not let its own download connection go idle, plus a scenario for a
  low-bitrate archive.

## Impact

- `Packages/FernsyPlayer/Sources/FernsyPlayer/HTTPByteSource.swift`: hold bookkeeping (when the
  hold started) and the resume rule in `resumeIfNeeded()`; a DEBUG override for the water
  marks.
- `DEVELOPMENT.md`: the new switch.
- Affects every non-live HTTP download: Xtream films, episodes, archive (catch-up) and Jellyfin
  direct play. Higher-bitrate media already drain within 15 s, so for them nothing changes.
