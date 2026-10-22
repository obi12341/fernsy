# Proposal

## Why

After a long pause in a Jellyfin film, playback continues for a few minutes and then stops as if
the film had ended, offering only "Play Again". While paused the download is held (the player
has 24 MB ahead), the idle connection is closed by the server or a proxy, and Fernsy treats any
cleanly closed download of a film as the end of the file (`HTTPByteSource`, `finished = true`),
although it knows the file's size. The remaining buffer plays out and the session reports the
end. Worse, Jellyfin playback then reports the full runtime as the stop position, so the server
marks the film as watched and its resume point is lost; for episodes the next-episode countdown
starts.

## What Changes

- **A – continue the download:** when a film's connection ends before the file's end (clean
  close or connection error), Fernsy reopens it with a range request at the next byte it needs
  and keeps the data already buffered; playback does not notice. Limited attempts; a server
  without range support or repeated failures end in an error, never in "ended".
- **B – plausible end only:** an end of playback well before the item's known duration (more
  than 60 s before it) is treated as an interruption: Fernsy loads the item again at the current
  position once (for a transcode: restarts it there); if that fails it shows an error. Only a
  real end reaches "ended" – so Jellyfin is never told the film was watched to the end by
  mistake.
- Applies to all on-demand network playback: Jellyfin direct play and transcodes, IPTV films and
  series. Live TV keeps its own reconnect.

Out of scope:
- Measuring when servers close idle connections (not needed; A works regardless).
- Closing the connection on purpose during long pauses.
- Recordings from local files.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `playback`: new requirements – on-demand downloads continue after a dropped connection, and
  playback only ends at the real end.

## Impact

- `Fernsy/Player/HTTPByteSource.swift` (continue at the buffer's end, test hook),
  `Fernsy/Player/PlayerEngine.swift` / `PlaybackSession.swift` (plausibility of the end, reload at
  the position), `Fernsy/Jellyfin/JellyfinPlayback.swift` (no change expected: the stop report
  follows the engine state), `README.md`.
