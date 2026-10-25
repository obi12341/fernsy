# Design

## Context

**Today:**
- `PlayerEngine` owns an `AVSampleBufferDisplayLayer`, whose `sampleBufferRenderer` is the
  video renderer, plus an `AVSampleBufferAudioRenderer` and an
  `AVSampleBufferRenderSynchronizer`. Both renderers are attached with `addRenderer`.
- `PlaybackSession` gets the renderers and enqueues from its own output threads:
  - video in a loop that paces frames to at most 0.3 s ahead of the clock, with a short wait
    on `isReadyForMoreMediaData`;
  - audio in a loop that paces to 1 s ahead.
- Flushes:
  - the session flushes on seek and reset (serial changes);
  - `PlayerEngine` flushes on load and stop, on `controlQueue`;
  - `PictureInPicture.end()` calls the deprecated `layer.flush()`.
- `PictureInPictureLoadingCard` enqueues its own frames into the same video renderer until
  the session's first frame (`beforeFirstVideo`).
- The only automatic-flush handling is the notification `…AudioRendererWasFlushedAutomatically`
  on `.main`, which refills audio.
- The tuner (headless ingest) creates renderers and a synchronizer that are never used.

**The macOS 27 receiver API, from the SDK's Swift interface:**
- `synchronizer.sampleBufferReceiver(adding: renderer) -> sending Receiver`, one each for
  `AVSampleBufferVideoRenderer` and `AVSampleBufferAudioRenderer`.
- `Receiver.enqueueImmediately(_: CMReadySampleBuffer<DynamicContent>) -> EnqueueResult`
  (synchronous), and `enqueue(_:) async throws`.
- Video `EnqueueResult`: `.enqueued`, `.enqueuedWithDecodeFailures([Error])`,
  `.cancelledDueToFlush`, `.cancelledDueToFlushRequiredToResume(Error)`.
- Audio `EnqueueResult`: `.enqueued`, `.enqueuedWithSuggestedFlush([SuggestedFlushReason])`,
  `.cancelledDueToFlush`.
- `flush()`, video `flush(removingDisplayedImage:) async`, audio
  `flush(fromSourceTime:) async`.
- `renderingEventsAfterFinishedEnqueuing`: an async sequence of rendering events (video
  `requiresFlushToResumeDecoding`, audio `wasFlushedAutomatically(at:)`).
- `CMReadySampleBuffer<DynamicContent>(unsafeBuffer: sending CMSampleBuffer)`.
- `Receiver` is not `Sendable`.

## Goals / Non-Goals

**Goals:**
- No deprecated renderer API.
- Decoder and output problems are recognized per enqueue and handled.
- Behaviour unchanged otherwise.

**Non-Goals:**
- Converting the pipeline to Swift concurrency.
- CPU savings.
- The other warnings.

## Decisions

### 1. Keep the threads, use `enqueueImmediately`

The session already paces both outputs (video ≤ 0.3 s, audio ≤ 1 s ahead), so the renderer
queues stay bounded without readiness checks. The output loops call `enqueueImmediately` and
evaluate the result. Readiness polling goes away.

Rejected: **`async enqueue` on detached tasks.** It needs a rewrite of the output loops and
their locking, or a semaphore bridge per frame (about 60–150 tasks per second), for a
benefit pacing already provides.

### 2. Sinks own the receivers

`final class VideoSink` and `final class AudioSink` (`@unchecked Sendable`) each hold a
receiver and an `NSLock`. Every receiver call (enqueue, flush) runs under the lock, so the
session thread, `controlQueue` and the main thread never use a receiver at the same time.

API:
- `enqueue(_ sample: CMSampleBuffer) -> Outcome`, converting with
  `CMReadySampleBuffer(unsafeBuffer:)`;
- `flush()`;
- video: `flushRemovingImage()`, which wraps the async flush in a `Task` and is used on stop;
- an `events` task that forwards the rendering events to a closure.

`PlayerEngine` creates the sinks once, next to the synchronizer. `PlaybackSession` and
`PictureInPictureLoadingCard` get the sinks instead of renderers. The headless tuner gets
none (`nil`); its code paths never reach the output.

**The last picture.** `lastPicture` (the frame kept for zapping and the PiP loading card)
takes the image buffer **before** the sample is handed over (`sending`). It already does so
by order; this only becomes mandatory.

### 3. Handling the results

| Result | Reaction |
|---|---|
| video `.cancelledDueToFlushRequiredToResume` | log a warning; `session.recoverVideo()`: serial+1, flush, resume at the clock's position from the next key frame (the existing seek path; live within the timeshift buffer); at most once per 2 s |
| video `.enqueuedWithDecodeFailures(errors)` | `decodeFailures += errors.count`, shown in the technical info as "Decodierfehler", logged with a limit (one line per 10 s) |
| video `.cancelledDueToFlush` | nothing (an expected race with a flush) |
| audio `.enqueuedWithSuggestedFlush(reasons)` | the same as the old notification: refill audio from the current position, once per burst |
| audio `.cancelledDueToFlush` | nothing |

The rendering-events sequence carries the same signals when they arrive after enqueuing has
stopped (for example during pause). `PlayerEngine` consumes it in a task per sink and handles
it the same way as the results.

### 4. Picture in Picture

- The loading card enqueues through `VideoSink` (`enqueueImmediately`). Its frame rate
  (timer) is unchanged.
- `PictureInPicture.end()` calls the video sink's `flush()` instead of `layer.flush()`.
- Open question for checkpoint 1: whether `AVPictureInPictureController` with
  `ContentSource(sampleBufferDisplayLayer:)` keeps working when the layer's renderer is fed
  through a receiver. If not, the change is abandoned (see the way out).

### 5. Checkpoints and the way out

Everything happens on `change/renderer-receiver-api`. Nothing is merged before checkpoint 3.

1. **Checkpoint 1, spike** (live on the demo server, a film, PiP in and out, the loading
   card): picture, sound, sync and PiP are as before.
2. **Checkpoint 2, full paths:**
   - timeshift (pause, rewind, back to live);
   - reconnect (`IPTV_TESTNET`);
   - recordings playback, including while recording;
   - zapping with the last picture;
   - Dolby Vision fallback (demo media);
   - the simulated recovery switches.
3. **Checkpoint 3, the user:** Jellyfin (direct and transcode), sleep/wake, an audio device
   change (AirPods), several hours of live TV.

If a checkpoint shows a regression that cannot be fixed without large rework (sync drift,
PiP, crashes, black pictures), the branch stops. `design.md` on the branch records why;
`main` keeps the old API and its warnings.

### 6. Testing without the user's input or stream slot

All tests run on the demo server with `FERNSY_NO_KEYCHAIN`, and only when the user's Fernsy
is not running. Debug switches:
- `IPTV_TESTFLUSHREQUIRED=<s>`: after `s` seconds, the video sink treats the next result as
  `cancelledDueToFlushRequiredToResume`, which tests recovery;
- `IPTV_TESTDECODEFAIL=<n>`: reports `n` decode failures, to check the info overlay.

A real sleep/wake and a device change are the user's checkpoint 3.

## Risks / Trade-offs

- **[The API is new in macOS 27 and little used]** → The checkpoints and the way out.
- **[Locks around receiver calls]** → The calls are short and the lock is uncontended in the
  normal case (one producer per sink). An async flush on stop runs in a task and does not
  hold the lock while it waits.
- **[`sending` and Swift 5 mode]** → The project compiles in Swift 5 mode; region-isolation
  diagnostics are warnings there. The task list requires a build without new warnings in
  these files.
- **[Recovery loops]** → Recovery happens at most once per 2 s; after 3 attempts in 30 s the
  session reports an error status ("Bild konnte nicht wiederhergestellt werden"), so it never
  loops silently.
