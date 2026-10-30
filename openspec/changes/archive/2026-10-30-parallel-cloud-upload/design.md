# Design

## Context

See proposal.md – Why. add-recording-cloud design D defines the upload:
- **Parts:** each part is 16 chunks (16 MiB + 256 bytes) and is recomputed from the local file.
  Finished parts are kept as ETags in the queue's JSON file.
- **Sending:** parts go directly to R2 through presigned UploadPart URLs, fetched in batches of
  50 (`CloudClient.partURLBatch`) and renewed after 50 minutes.
- **Queue:** one recording uploads at a time, in a foreground `URLSession`.

Today `CloudUploadQueue.upload(_:)` loops over the parts in order. For each part it encrypts
(`CloudFileEncryptor.bytes(in:)`, on the main actor), then awaits `put`, then saves the ETag.

Measured on the user's Mac, 2026-10-30:
- AES-GCM with 1 MiB chunks: about 6.5 GB/s, so encryption costs about 3 ms per part.
- At 200 Mbit/s a part needs about 0.7 s on the wire. R2's answer and the next request add a
  round trip with no data, and TCP ramps up again. That fits the observed rate of a little over
  half the line.

## Goals / Non-Goals

**Goals:**
- One upload saturates a 200 Mbit/s upstream, or comes close to it.
- Resume, cancel, quota and the 403 renewal behave as before.

**Non-Goals:**
- Moving encryption off the main actor. At about 3 ms per part, four parallel parts keep the
  main actor busy for well under 1 % of the time.
- Uploading several recordings in parallel, or adaptive concurrency.

## Decisions

### A. A bounded task group of four parts

`upload(_:)` collects the missing part numbers in ascending order. It runs a `TaskGroup` that
keeps at most `CloudUploadQueue.parallelParts = 4` parts in flight. Whenever one finishes, it
records the ETag, saves the state, and starts the next part. Each child task:
1. encrypts its part on the main actor (the encryptor's file handle is not thread-safe);
2. awaits the `put`, which runs in `URLSession` off the main actor.

Four parts are about 64 MiB of buffers. Four connections to the R2 host use HTTP/2 or
parallel HTTP/1.1, so the window and round-trip gaps of one connection no longer limit the
rate.

Rejected:
- **Larger parts (for example 64 MiB) sent one at a time:** this would shrink the gaps but keep
  one TCP stream, and a retry would resend 64 MiB. It would also change the part size in design
  D, which running uploads have saved.
- **A background `URLSession` with upload tasks:** it needs encrypted files on disk (design D,
  rejected there).
- **Eight or more parts:** more memory and more retries after a network loss, for little gain
  at 200 Mbit/s. Four can be raised later as a constant.
- **Pipelining the encryption of part n+1 while part n is sent (option 2):** the user chose to
  leave it out. With parallel parts it would gain nothing measurable.

### B. Part URLs are merged, not replaced

`putPart` currently replaces the whole `urls` dictionary when it fetches a batch. With parts in
flight, that could drop a URL that another task is about to use. Fetched batches are therefore
merged into the dictionary. A refresh after 50 minutes or a 403 still fetches the batch
starting at the part that needs it. Two tasks that both need a refresh may fetch twice, which
is harmless.

### C. Failure and cancellation

- **One part fails:** the first error from a child cancels the group. Parts that already
  finished keep their saved ETags. The queue's existing handling (`waiting`, then retry) runs
  as before, and the retry uploads only the missing parts, in any gaps.
- **Cancel:** cancelling the worker task cancels the in-flight `URLSession` uploads, which
  throws `CancellationError`. Then the existing `cancel` path deletes the upload on the server.
- **Completion:** `complete` sends the parts sorted by number, as before. R2 needs every part
  from 1 to n, and those are present once the group ends without an error.

### D. Throughput in the log

When an upload completes, `AppLog.info` records the bytes, the seconds and the Mbit/s of that
run. If the upload resumed, only the bytes sent in that run count. This is the measure for
task 3.2. The log never contains URLs or keys.

## Risks / Trade-offs

- [More memory during uploads, about 64 MiB] → fine on a Mac. The constant can be lowered if
  needed.
- [The Mac's uplink is saturated during an upload, so a live stream's control traffic or a
  video call could suffer] → the stream is download traffic and the upload has no priority
  over it. If it becomes a problem, a pause or limit is a later change.
- [R2 rejects many parallel UploadParts of one upload] → S3 multipart allows parallel parts. It
  is checked against the dev worker in task 3.1.
- [Parts finish out of order and a crash loses the order] → each finished part is saved by
  number with its ETag. The order is restored at completion by sorting.

## As built

Measured on 2026-10-30 from the user's Mac against `fernsy-cloud-dev`, with a 587 MB demo
recording uploaded by `CloudClientTests/uploadUITestFixture` (the same `CloudUploadQueue` as
the Mac app, without the app around it):
- `parallelParts = 1`: 37.4 s, 126 Mbit/s. That matches the "a little over half" the user saw.
- `parallelParts = 4`: 14.0 s, 335 Mbit/s.

The iPad simulator played and seeked the 4-part upload (`testCloudRecordingPlaysAndSeeks`
with `TEST_RUNNER_FERNSY_CLOUD_FIXTURE_ID` set to its id). Both test uploads were deleted
afterwards.

Cancelling now waits for the parts in flight before it deletes the upload on the server.
Before, the single part could still finish after `cancel` returned. Cancelling one job
continues the queue with the next one and does not stop the worker.
