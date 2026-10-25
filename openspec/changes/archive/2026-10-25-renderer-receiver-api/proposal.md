# Proposal

## Why

The player's renderer calls are deprecated in macOS 27. About 20 build warnings concern
`enqueue`, `flush`, `isReadyForMoreMediaData`, `addRenderer` and the notification
`…WasFlushedAutomatically`. Apple's replacement is the **receiver API**: per renderer a
`Receiver` obtained from the render synchronizer, whose `enqueue` returns a result.

What this brings Fernsy:
- **A self-healing player.** Each enqueue reports `enqueuedWithDecodeFailures`,
  `cancelledDueToFlushRequiredToResume` (the decoder needs a flush and a key frame, for
  example after sleep, a display or GPU change, or a broken stream) and, for audio,
  `enqueuedWithSuggestedFlush` (output device changed). Today Fernsy only reacts to the audio
  case, through a notification on an arbitrary thread that Apple itself describes as racy.
  A decoder that needs a flush is not handled at all, so the picture can freeze until the
  user switches channels.
- **No deprecated API in the core.** The warnings go away before Apple removes the old calls.

Not a gain: CPU. Fernsy paces video to at most 0.3 s ahead and audio to 1 s, so the renderer
is almost never full. The readiness polling (`Thread.sleep(0.004)`) rarely runs.

The user asked for this on its own branch. If the new API causes problems during the work,
the branch is dropped and the old API stays.

## What Changes

- **Receivers instead of renderer calls.** `PlayerEngine` creates the receivers once
  (`synchronizer.sampleBufferReceiver(adding:)` for `displayLayer.sampleBufferRenderer` and
  the audio renderer) and wraps each in a small lock-guarded sink (`VideoSink`, `AudioSink`).
  The playback session, the Picture in Picture loading card and stop/flush only use the
  sinks.
- **Enqueue stays on the session's threads.** `enqueueImmediately` with the result
  evaluated; frames become `CMReadySampleBuffer(unsafeBuffer:)`. The last picture is taken
  before the hand-over. No switch of the pipeline to Swift concurrency.
- **Recovery:**
  - **Video `cancelledDueToFlushRequiredToResume`:** flush, then resume at the current
    position from the next key frame (the existing seek path; live: the timeshift buffer at
    the live edge). Logged under `player`.
  - **Video `enqueuedWithDecodeFailures`:** counted in the technical info and logged.
    Playback continues.
  - **Audio `enqueuedWithSuggestedFlush` / `wasFlushedAutomatically`:** replaces the
    notification; audio is refilled from the current position as today.
- **The tuner (headless) creates no renderers or receivers.**
- **Picture in Picture.** The loading card enqueues through the same video sink. The flush at
  the end of PiP goes through the sink.

Out of scope:
- switching the pipeline to `async enqueue`;
- the other build warnings (`[weak self]`, `httpShouldUsePipelining`), which are a separate
  cleanup.

**Way out:** the work happens on `change/renderer-receiver-api`. If a checkpoint fails
(design), the change is abandoned, nothing is merged, and the reason goes into `design.md`.

## Capabilities

### New Capabilities
- (none)

### Modified Capabilities
- `playback`: new requirement "Decoder recovery" (the picture recovers by itself when the
  decoder needs a restart; decode failures are visible in the info overlay).

## Impact

- `Fernsy/Player/PlayerEngine.swift` (synchronizer setup, flush on load/stop, audio flush
  handling, technical info).
- `Fernsy/Player/PlaybackSession.swift`: video and audio output loops, flush on seek and
  reset, renderer parameters replaced by sinks, tuner init.
- `Fernsy/Player/PictureInPicture.swift`: loading card and the flush at the end of PiP.
- New `Fernsy/Player/RendererSinks.swift`.
- Every playback path must be retested: live, timeshift, film, Jellyfin (direct and
  transcode), Dolby Vision fallback, PiP, recordings, reconnect, audio device change.
