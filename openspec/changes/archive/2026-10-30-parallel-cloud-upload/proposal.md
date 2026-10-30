# Proposal

## Why

A Fernsy Cloud upload reaches only a little more than half of the user's 200 Mbit/s
upstream. Encryption is not the cause: AES-GCM on the Mac seals about 6.5 GB/s. The upload
sends one 16 MiB part at a time and waits for R2's answer before it starts the next one. The
line is idle during each round trip, and TCP has to ramp up again for every part. A 3 GB
recording therefore takes almost twice as long as the line allows.

## What Changes

- The Mac uploads several parts of one recording at the same time, four by default. The parts
  keep their size and numbering, so the object in R2 and its format stay the same.
- Resuming keeps working with parts finished out of order. Every finished part is saved with
  its ETag as soon as it is done. After a quit or a network loss, only the missing parts are
  uploaded.
- When an upload finishes, the log records its duration and throughput, so the speed can be
  compared.
- Out of scope:
  - moving encryption off the main actor (option 2 of the discussion; the user chose 1 and 3);
  - uploading several recordings at once (the queue stays one recording at a time);
  - changing the part size;
  - changing the server or the file format;
  - a user setting for the number of parallel parts.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `recording-cloud`: a new requirement that an upload keeps several parts in flight and
  resumes from any set of finished parts. The capability is added by the unarchived
  `add-recording-cloud` change, so the delta adds a requirement rather than modifying one.

## Impact

- `Packages/FernsyCore/Sources/FernsyCore/CloudUploadQueue.swift`: the part loop becomes a
  bounded task group, and the part-URL cache merges batches.
- `Packages/FernsyCore/Tests/FernsyCoreTests/CloudUploadQueueTests.swift`: tests for the
  parallelism limit, resuming with gaps, and cancelling while parts are in flight.
- Mac memory during an upload grows from about 16 MiB to about 64 MiB of part buffers.
- No changes to the server, the iOS or tvOS apps, or the stored data.
- Archive order on `change/add-recording-cloud`: `add-recording-cloud`, then
  `cloud-account-from-icloud-key`, then this change.
