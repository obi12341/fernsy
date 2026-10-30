# Tasks

## 1. Upload queue

- [x] 1.1 `CloudUploadQueue.upload(_:)`: a `TaskGroup` with at most `parallelParts = 4` missing parts in flight. Each part is encrypted on the main actor; its ETag is saved as soon as it finishes; the first failure cancels the group (design A, C). Verify with `swift test --filter CloudUploadQueueTests` in `Packages/FernsyCore`: the existing tests still pass.
- [x] 1.2 `putPart`: merge fetched URL batches into `urls` instead of replacing them (design B). Verify with a test in which a batch boundary (part 51) is crossed while parts 49 and 50 are in flight, using the fake API with 60 parts of small size via an injectable part count, or a fake that counts `partURLs` calls; no part fails with `no_part_url`.
- [x] 1.3 Log duration and throughput of each completed upload (design D). Verify that the log line appears in the test run output and contains no URL.

## 2. Tests

- [x] 2.1 `CloudUploadQueueTests`: the fake `put` waits briefly and records the concurrency. Verify that the maximum is 4, never 5, and is greater than 1.
- [x] 2.2 Resume with gaps: the fake fails part 3 once while 1, 2 and 4 succeed. Verify that after resume only the missing parts are put (no part twice) and the completed object decrypts to the file.
- [x] 2.3 Cancel while parts are in flight. Verify that the queue is empty, the server upload is deleted, and no part is put after the cancel returns.

## 3. Verification

- [x] 3.1 Mac Debug build against the dev worker (`IPTV_CLOUD`, `IPTV_CLOUDTOKEN`, `IPTV_CLOUDKEY=local`; values in DEVELOPMENT.md › Fernsy Cloud). Upload a demo-server recording of at least 500 MB. Verify that it completes, that the iPad simulator plays it with the same switches, and note the Mbit/s from the log next to a run with `parallelParts = 1`.
- [x] 3.2 Release Mac build with `FERNSY_CLOUD = YES` on the user's Mac against production. The user uploads a real recording. Verify that the logged Mbit/s comes close to the 200 Mbit/s line; the user confirms it. *2026-10-30: 6.99 GB at 347 Mbit/s and 1.77 GB at 323 Mbit/s on production; the user confirmed.*
- [x] 3.3 Run `openspec validate --all --strict` and `scripts/test.sh`. Both must pass.

## Workflow follow-up

- On `change/add-recording-cloud`: archive `add-recording-cloud`, then `cloud-account-from-icloud-key`, then this change. Then merge into `main` and push, with the user's consent.
