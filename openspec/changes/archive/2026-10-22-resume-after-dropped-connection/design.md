# Design

## Context

- `HTTPByteSource` downloads a film over one long request and holds it (`task.suspend()`) when
  more than 24 MB (`highWater`) are buffered ahead – a long pause keeps the connection idle.
- On completion of a non-live task: `error == nil` → `finished = true` (EOF to FFmpeg); an error →
  `failure`. `contentLength` (from `Content-Range` or `Content-Length`) and `supportsRanges` are
  known; `connect(at:)` (used by seeks) reopens with `Range: bytes=<offset>-` but clears the
  buffer.
- `PlaybackSession` sends `.ended` after EOF once both queues drained; `PlayerEngine` sets
  `status = .ended` for non-live items. `JellyfinPlayback.stop()` reports the full duration as
  the stop position when the status is `.ended`.
- Live TV has its own path (`streaming`, `liveReconnect`) and is not changed.

## Goals / Non-Goals

**Goals:** an interrupted film download continues invisibly; a premature end never looks like
the real end, so no false "played" reaches Jellyfin.

**Non-Goals:** see proposal.

## Decisions

### A: Continue at the end of the buffer
On completion of a non-live task, Fernsy compares the downloaded end
(`bufferBase + buffer.count`) with `contentLength`:
- complete (`>= contentLength`) or length unknown and no error → EOF as today;
- otherwise (clean early close, or a connection error that is not a cancellation) and
  `supportsRanges` → `continueDownload()`: a new task with `Range: bytes=<bufferEnd>-` that keeps
  `buffer`, `bufferBase` and `readIndex`; the response must be a 206 whose `Content-Range` starts
  at `bufferEnd`, otherwise it fails. Readers waiting in `read()` keep waiting (deadline as today).
  Up to 5 attempts per incident with a growing pause (0.5, 1, 2, 4 s); an attempt that receives
  data resets the count. A held (suspended) task whose connection died is noticed when it is
  resumed or completes; the same path applies.
- Without range support or after the attempts: `failure` with a clear message ("Verbindung zum
  Server verloren"), never EOF.
- Rejected: closing the connection deliberately after N minutes of pause – needs a guess about
  server timeouts and does not cover drops while playing.
- Rejected: reusing `connect(at:)` – it clears the buffer and would make FFmpeg re-read data it
  already has.

### B: Plausible end
`PlayerEngine` checks `.ended` for non-live items with a known duration (`progress.duration > 0`):
if the position is more than 60 s before the duration, it is an interruption:
- once per position (no loop): reload the same URL at the current position (`start(url:…,
  startAt: position)`), or for a controller with `restartAt` (Jellyfin transcode) call it with the
  position;
- if that again ends early, or fails, `status = .failed("Wiedergabe unterbrochen")`.
`JellyfinPlayback.stop()` only reports the full duration for a real `.ended`, so a failure keeps
the actual position (no code change needed beyond the engine never reaching `.ended` early).
- Rejected: trusting EOF – the cause of the false "played".
- 60 s margin: credits and rounding of durations in containers; anything earlier is not a real
  end.

### Testing hook
`IPTV_TESTNET` gains `close:<s>`: the current download completes as if the server had closed it
cleanly (no error), which today produces the false end. Together with `IPTV_TESTPAUSE` it
reproduces the pause case on the demo server's films (range-capable mp4).

## Risks / Trade-offs

- [Server ignores the range on continue] → detected via status/`Content-Range`, ends in an error
  instead of corrupt data.
- [Files whose duration metadata is too long] → B would reload once at the end and then show an
  error instead of "ended"; acceptable, rare, visible.
