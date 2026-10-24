# Design

## Context

A recording starts in `Recorder.begin`. It resolves connection conflicts, acquires a
`LiveTuner` from the `TunerPool` as `.recording(id)`, and waits for the first data. The wait
loop ends after `30 + tuneAhead` (50) seconds, or as soon as the tuner is no longer active.
If the buffer has no entry by then, the recording becomes `.failed` with "Keine Daten vom
Sender" and is never tried again.

`TunerPool` sets `keepTrying` on a tuner while a recording owns it. `LiveTuner.restart` then
retries retryable failures without limit (every 0.5 to 10 s). Non-retryable failures end
the tuner with `.failed`. These are `PlayerError.offline` (provider redirect to the offline
placeholder) and `PlayerError.unsupported`. Because of that, two paths lose a recording for
good:

1. Start: no data within 50 s (the channel stays silent, every connect fails or times out),
   or the provider reports the channel offline (tuner `.failed`, the loop ends at once).
2. During the show: if the provider reports the channel offline after a reconnect, the tuner
   becomes `.failed`. `tick` then finishes the recording as failed, though its window is
   still open.

On restarts, the tuner keeps its `TimeshiftBuffer` and `TimeshiftWriter`. `connect()` only
replaces the session, and the writer keeps the timeline continuous. A `RecordingCopier`
reading that buffer therefore simply continues after an outage.

## Goals / Non-Goals

**Goals:**
- A recording gets data whenever the channel delivers anything within its window.
- An outage during a recording continues in the same file.
- The user can see that a recording is waiting, and can stop it.

**Non-Goals:**
- Recordings missed while Fernsy was closed, or skipped in the connection prompt.
- Player-only retries, films and Jellyfin.
- Notifications.

## Decisions

### 1. The recording is "running" from its start, with or without data

Once the conflict check passes, `begin` sets the status to `.recording`, with `fileName`
still nil, and then waits for data. The copier and the file are created when the first
buffer entry exists. While `fileName` is nil, the row shows "Wartet auf den Sender …". The
"Läuft" section, the stop button, the quit prompt (`hasActiveOrUpcoming`) and keeping the Mac
awake (`updateActivity`) all work without changes, because they already key on
`.recording`.

The wait loop runs while the entry is `.recording` without a copier and `Date() <
recordEnd`. Stopping the recording (user or `tick`) ends it. A copier is only created if
the entry is still `.recording`. In any other case the tuner is released.

`finish` without a copier marks the entry `.failed` with "Keine Daten vom Sender" and
leaves `bytes` nil. This covers three cases: the window ends without data, the user stops a
waiting recording, and the app quits. On relaunch, the existing `activate` logic turns a
`.recording` entry without a file into `.failed`, which stays correct.

Rejected: a separate, non-persisted `waiting` set next to `.scheduled`. Every place that
asks "is a recording running" (sections, quit prompt, awake, `tick`'s missed rule) would
need a second condition. `tick` would also mark a still-waiting entry as `.missed` when the
window ends.

Rejected: a new persisted status `.waiting`. It is the same as above. Older list files
would also need a migration for no gain.

### 2. Offline is retried while a recording owns the tuner

In `LiveTuner.handle`, a non-retryable failure is treated like a retryable one when
`keepTrying` is set, with one exception: `writer.isFailed` (`.unsupported`, the streams
cannot be remuxed) stays final. The retry delay after an offline report is 30 s instead of
the usual backoff. The provider is asked about twice a minute, which keeps load low. The
state is `.reconnecting`, so `isActive` stays true, and `tick` no longer ends the recording.
If only the player owns the tuner, the behaviour is unchanged (the offline message, no
endless retries). `TunerPool.updateKeepTrying` already sets the flag when a recording
releases or acquires the tuner.

`PlayerError.unsupported` from `openInput` stays final as well. Retrying a stream that
cannot be handled only produces load.

Rejected: retrying in `Recorder` by releasing and re-acquiring the tuner. A new tuner has a
new buffer and timeline, so a running copier would need a second file or would have to
append a stream with a timestamp jump. It would also briefly free the connection slot, and
the player could take it in that moment.

### 3. The file starts with the first data

`TimeshiftBuffer.entry(atOrBeforeWall:)` already returns the first entry when all data is
newer than the requested time. A late recording therefore starts at its first keyframe
after the outage. The show times in the list stay as planned. The size and the file content
show what was actually recorded.

### 4. Debug switch for verification

`IPTV_TESTNODATA=<offline|silent>:<seconds>` (DEBUG only, read in `PlaybackSession` for
tuner sessions). For that many seconds after app start, every tuner `openInput` either
throws `PlayerError.offline` or waits 8 s and throws a timeout (a silent channel). The
demo server stays unchanged.

## Risks / Trade-offs

- A channel that is really gone keeps a connection slot busy for the whole recording window
  and is polled every 30 s. This is intended: the user planned the show. On a single-stream
  account, the player cannot use the slot during that time. The existing conflict prompt
  asks before the player switches away, so the user can stop the waiting recording.
- A recording that starts late has no marker for the gap at its beginning. The list only
  shows the size. This is acceptable for now; a "started late" note can follow later if
  needed.
