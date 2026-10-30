# Design

## Context

See proposal.md – Why. The current state that shapes the approach:

- **Recordings.** Only the Mac records, to `~/Movies/Fernsy/*.ts` (the `recordings` spec). The
  recorder is shared in `FernsyPlayer/Recorder.swift`, and `Fernsy/Recording/MacRecorderHost.swift`
  holds the Mac's parts. The Apple TV records only while the app is open, into Caches
  (`2026-10-27-tvos-live` design C/D). The iPad and iPhone app has no Recordings section.
- **Player input.** Every player reads through `FernsyPlayer.ByteSource` (`read`/`seek`, which
  FFmpeg's AVIO calls). Implementations are `HTTPByteSource`, `BufferByteSource` and
  `FileByteSource`. A new source can feed any player without touching FFmpeg.
- **Secrets across devices.** iCloud Keychain does not reach tvOS. The logins are already kept
  in the private CloudKit database in `encryptedValues`, which is end-to-end encrypted and
  works on Mac, iOS and tvOS (`2026-10-28-icloud-sync` design B, `LoginSync.swift`).
  `ubiquityIdentityToken` is nil on tvOS, so availability is checked with `accountStatus()`.
- **Workers.** The demo server is a plain-JS Cloudflare Worker, deployed through the
  Cloudflare API by `demo-server/deploy.sh`, without wrangler or npm.
- **R2.** Upload parts must all have the same size except the last, and be at least 5 MiB.
  Presigned URLs work only on the `<account>.r2.cloudflarestorage.com` S3 endpoint.

## Goals / Non-Goals

**Goals:**
- The operator holds only ciphertext, random ids, sizes and times.
- Players can seek in a recording without a full download.
- Interrupted uploads resume without starting over.
- The same crypto and API code is used on all three platforms (in `FernsyCore` and
  `FernsyPlayer`).

**Non-Goals:**
- Hiding sizes, upload times, the Apple user id or IP addresses from the operator.
- Key rotation in the UI. The format carries a key id so rotation can come later.
- A legal guarantee. End-to-end encryption means the operator cannot see content. Whether that
  is enough is part of the legal review, which the proposal keeps out of scope.

## Decisions

### A. One account key in CloudKit, one random key per recording

The account key is a random 256-bit key. The Mac creates it on the first upload; it is the
only device that uploads. The key goes into the keychain and into the private CloudKit record
`cloud.key` (`encryptedValues`, record name fixed). Saving uses `ifServerRecordUnchanged`. If
two Macs race, the loser fetches the stored key and uses it. Other devices only read the key.
If no key is found, they show "locked" and never create one, because a second key would make
the existing uploads unreadable.

Each recording has its own random file key. The file key and the details (title, channel,
times, gaps, plaintext size, outcome) form one JSON. It is sealed with AES-GCM under the
account key (random nonce, AAD `fernsy-meta-v1|<recordingId>|<keyId>`) and stored as the
object `<recordingId>.meta`.

Rejected:
- **iCloud Keychain**: it does not reach tvOS (icloud-sync design B).
- **A key held or escrowed by the server**: that would defeat the purpose.
- **A passphrase the user types on every device**: typing it on the Apple TV is painful, and
  a weak passphrase would be the weak point.
- **One key for all files with random nonces**: per-file keys make chunk nonces a plain
  counter without any collision risk, and keep later rotation cheap.

### B. Chunked AES-256-GCM data format (`FCR1`)

The data object `<recordingId>.data` is laid out as follows:
- A 16-byte header: magic `FCR1`, version, chunk size.
- Then chunks of 1 MiB plaintext each (the last one shorter). Each chunk is sealed with the
  file key, the nonce is the chunk index as a 96-bit big-endian number, and the AAD is
  `<recordingId>|<index>|<isLast>`. A chunk on disk is 1 MiB + 16 bytes.

From a plaintext offset follows the chunk, from the chunk its ciphertext range. The `isLast`
flag in the AAD exposes truncation, the index exposes swapped chunks.

CryptoKit is available on all three platforms. No FFmpeg encryption is used, so the LGPL
rule is not touched.

Rejected:
- **Encrypting the whole file in one go** (AES-GCM or ChaCha over the whole file): no seeking
  without a full download.
- **AES-CTR without authentication**: altered data would go to the demuxer unnoticed.
- **Encrypted HLS (AES-128 per segment)**: it would need segmenting and playlists, its
  metadata would stay readable, and the Fernsy player does not need it.

### C. `CloudByteSource` decrypts while streaming

`CloudByteSource` is a new `ByteSource` in `FernsyPlayer`:
- It maps FFmpeg's plaintext offsets to chunks and fetches ciphertext with HTTP range requests
  on the signed URL.
- It decrypts and serves the plaintext.
- It keeps a bounded read-ahead of 8 chunks and an LRU cache of at most 32 MiB, sized for the
  Apple TV's memory.
- On HTTP 403 (URL expired) it fetches a fresh URL through the API and repeats the request.
- A chunk whose tag fails ends playback with "damaged recording".

Only the input changes. As built, `PlaybackSession.Mode.file` takes any seekable `ByteSource`
instead of a new mode, and `PlayerEngine.load(cloud:)` passes the cloud source to it; the
player keys the item by `fernsy-cloud://recording/<id>`. A source can name its own failure
(`ByteSource.failureMessage`), so a damaged recording does not read as "Connection lost".
Resume positions use the key `cloud.<id>`, and tracks and player panels behave as for local files. No provider connection is
involved, so the single-stream rules do not apply.

Rejected: a local loopback HTTP proxy that decrypts. It needs an extra server and
`network.server` on iOS and tvOS, which the `ByteSource` interface makes unnecessary.

### D. Upload in fixed parts, resumable from the file

Each part is 16 chunks (16 MiB + 256 bytes), only the last is shorter. That gives every part
the same size, as R2 requires, and part *n* can be recomputed from the local file at any
time. The upload queue keeps its state in a JSON file under Application Support:
- recording id,
- file path or bookmark,
- the R2 upload id,
- the ETags of the finished parts.

After a restart the queue fetches fresh part URLs for the missing parts and goes on. One
upload runs at a time, in a foreground `URLSession` while the app runs, as required for the Mac
(no daemon).

The plaintext size is fixed at start. A recording has to be finished to be uploadable, so
its size no longer changes.

Rejected:
- **A background `URLSession` upload task**: it uploads from a file. A 3 GB encrypted copy on
  disk would be needed first, and the Mac app runs anyway.
- **Uploading through the worker**: Worker request bodies are limited, and it would double the
  traffic.

### E. Worker: plain JS modules, D1 and R2, deployed by API

`cloud-server/` mirrors `demo-server/`: plain ES modules uploaded by `deploy.sh` through the
Cloudflare API. It has these bindings:
- R2 `BUCKET`, for listing, HEAD and delete.
- D1 `DB`.
- A daily cron trigger.
- Secrets: R2 S3 access key and secret, session HMAC key, App Store Server API key (`.p8`,
  key id, issuer id), Apple bundle ids, and on the dev deployment only `DEV_TOKEN`.

Modules: `worker.js` (routes), `sigv4.js` (S3 presigning and signed requests with WebCrypto),
`apple.js` (identity token, App Store Server API) and `store.js` (D1). The logic is pure
functions, tested with `node --test` (`cloud-server/test/`), with no dependencies.

Multipart steps (create, complete, abort) run as signed S3 requests from the worker. The
parts are uploaded directly with presigned UploadPart URLs, which keeps all multipart steps on
one interface (task 1.1 checks this).

Spike result (task 1.1, 2026-10-30, bucket `fernsy-cloud-dev`, location EEUR): it works as
documented.
- A multipart upload created by a signed S3 `POST ?uploads` (region `auto`) accepted three
  parts PUT through presigned UploadPart URLs: two of 16 MiB + 256 B and a last one of
  1000 B.
- A signed `POST ?uploadId=…` with the XML part list completed it.
- A presigned GET with `Range: bytes=16777462-16777481` across the part boundary answered
  206 with exactly those bytes.

The S3 credentials come from a separate account token that may only read and write items in
that one bucket. The access key id is the token id, the secret is the SHA-256 hex of the
token value. The master token never goes into the worker.

Sign in with Apple audience: all apps share the bundle id `de.mobilistics.fernsy` (Debug:
`de.mobilistics.fernsy.dev`). The worker's `APPLE_AUDIENCES` lists both.

Objects are stored as `u/<userId>/<recordingId>.data|.meta`. `userId` is a random UUID created
at first sign-in, `recordingId` a random UUID from the worker.

D1:
- `users(id, apple_sub UNIQUE, created_at, original_transaction_id, product_id, expires_at, ended_at, quota_bytes)`
- `recordings(id, user_id, data_bytes, meta_bytes, state, upload_id, created_at, completed_at)`

The used storage is the sum over `done` plus the stated sizes of `uploading`, so parallel
starts cannot exceed the quota.

Routes (all except `/v1/session` and `/v1/apple/notifications` need `Authorization: Bearer <session>`):

| Route | Purpose |
|---|---|
| `POST /v1/session` | Apple identity token → session token (HS256, 90 days, renewed on use), user id |
| `GET /v1/account` | subscription state, expiry, ended/grace date, used/total bytes |
| `POST /v1/subscription` | transaction id from the app → status fetched from Apple |
| `POST /v1/apple/notifications` | App Store Server Notifications V2 |
| `GET /v1/recordings` | completed recordings: id, sizes, completed time |
| `POST /v1/recordings` | start: data and meta size → id, upload id, part URLs |
| `POST /v1/recordings/:id/parts` | fresh URLs for given part numbers |
| `POST /v1/recordings/:id/complete` | parts + ETags → complete, check size against quota |
| `GET /v1/recordings/:id/urls` | signed read URLs for `.data` and `.meta` (6 h) |
| `DELETE /v1/recordings/:id` | delete objects and row, or abort an unfinished upload |

The `.meta` object is small and uploaded with a single presigned PUT, returned with the start
answer.

Rejected:
- **wrangler and npm, or the aws4fetch package**: one more toolchain than the repo uses. SigV4
  presigning takes about 100 lines of WebCrypto.
- **A bucket per user**: the bucket count per account is limited, and it is no safer than key
  prefixes that only the worker chooses.
- **Mixing the R2 binding's multipart API with presigned S3 parts**: undocumented whether the
  two share upload ids.

### F. Subscription truth comes from Apple's server, not from the client

The subscription is bought before there is a Fernsy Cloud account (decision G), so it cannot
carry an `appAccountToken`. After sign-in the app sends the subscription's original
transaction id from StoreKit 2 (`Transaction.currentEntitlements`). The worker then:
- fetches the subscription status from the App Store Server API (ES256 JWT),
- checks bundle id and product id,
- links the original transaction id to the user, if no other user holds it, and stores the
  expiry.

A second device of the same user presents the same original transaction id and gets the same
user, because the Apple user id from sign-in matches. Another user presenting it is refused
(first claim wins).

For Server Notifications V2 the worker reads only the transaction id from the payload and
fetches the status again from the API. The payload's signature does not need to be verified,
since nothing in it is trusted. When an expiry passes without a notification, the cron job
and `GET /v1/account` ask the API again. `ended_at` is the expiry or the revocation time. The
cron job deletes users 30 days after `ended_at` and aborts uploads older than 7 days.

As built: the worker asks production first, then the sandbox. Production answers 401 (not 404)
while the app has no approved in-app purchase yet, even with a valid key, so a production 401
also falls through to the sandbox; a sandbox 401 is an error.

Rejected: verifying the JWS certificate chain (x5c up to Apple Root CA G3) in the worker. That
needs X.509 parsing without libraries, and asking Apple's API directly gives the same trust
with less code.

### G. Sign in with Apple on all three apps, only when cloud is used

The service needs its own account, since the subscription and the storage belong to a user and
not to a device. "Sign in with Apple" is available on macOS, iOS and tvOS and needs no
password.

The prompt comes only when it is needed (user decision 2026-10-30):
- On the Mac when the global switch "Upload recordings to Fernsy Cloud" is turned on. The
  order is: subscription first (buy or restore), then sign-in, then the switch is on.
- On iPad, iPhone and Apple TV the first time a subscriber opens the cloud recordings.
  Whether a subscription is active is known there from StoreKit without an account.

Users without a subscription never see a prompt. The session token is kept in the device
keychain and renewed on use. On 401 the app asks again at the next cloud action, not at
launch.

Rejected:
- **The CloudKit user record id as identity**: the worker cannot verify it.
- **Email and password**: it would need its own password handling, and App Review would
  require Sign in with Apple next to it anyway.

### H. Hidden behind a build switch until launch

All cloud UI is shown only when the build setting `FERNSY_CLOUD = YES` or the debug switch
`IPTV_CLOUD=<server URL>` is set. That way the code can be merged into `main` and released
without the service being visible before the product and the legal review are ready.

`IPTV_CLOUDTOKEN=<dev token>` signs in on the dev server without Apple. `IPTV_CLOUDKEY=local`
keeps the key only in the keychain, because simulators in UI tests have no iCloud. As built,
`IPTV_CLOUDKEY=<base64 key JSON>` uses a given key in memory instead, so UI tests can read a
fixture uploaded with that key. These switches work only in Debug builds.

As built, the Info.plist key `FernsyCloud = $(FERNSY_CLOUD)` is in the Mac's and iOS's plists.
The Apple TV's `Info-TV.plist` had unrelated uncommitted edits in the working copy, so its key
is still to be added; until then the Apple TV shows the cloud only with `IPTV_CLOUD`. The DMG
build (Fernsy Direct) gets no cloud: in-app purchases need the App Store.

The Mac's automatic queue takes recordings that finish while Fernsy runs and whose writer has
reported its bytes (the file is final then), and only once each. Recordings that were already
finished at launch are not queued by themselves; they get "Upload to Fernsy Cloud". A recording
whose local file is gone plays from the cloud in its own row.

## Risks / Trade-offs

- **[Lost key = lost recordings]** for example after an iCloud data reset or another Apple
  ID. → The account screen says so in plain words. The recordings stay listed as locked and
  can still be deleted, so storage can be freed.
- **[Metadata the operator still sees]** sizes, times, Apple user id, IP addresses. → Stated
  in the privacy text at launch. Recording ids are random and object names carry nothing else.
- **[R2 multipart details]** whether S3 presigned parts and server-side Complete behave as
  documented. → Task 1.1 checks this on the dev bucket before any app code depends on it.
- **[Apple TV memory and network]** → Bounded read-ahead and cache (decision C). If the 1 MiB
  chunk size makes seeking feel slow, the next format version can change it; the size is in
  the header.
- **[Cost abuse, the operator cannot see what is stored]** → Quota per subscription, uploads
  only for active subscribers, deletion 30 days after the end.
- **[Claiming another user's subscription]** The original transaction id is not a secret
  proof. Someone who learns it could link it first. → Ids are only on the buyer's devices.
  On a dispute, support can unlink it in D1. If it ever happens, presenting the signed JWS and
  verifying its certificate chain (rejected in F) becomes worth its cost.
- **[Signed URL leaks]** → Short lifetimes, and the content is ciphertext anyway.
- **[App Review]** IAP for storage and Sign in with Apple are standard. Until launch the
  feature is hidden (decision H).

## Migration Plan

1. Create the R2 bucket `fernsy-cloud-dev`, the D1 database and the S3 token, and deploy the
   dev worker.
2. Build the app work against the dev worker, with the StoreKit configuration file for local
   purchase tests.
3. Before launch, outside this change: create the production bucket, D1 and worker
   `fernsy-cloud`, the App Store Connect product and Server API key, point the notification
   URL at it, and set `FERNSY_CLOUD = YES`.
4. Rollback: turning `FERNSY_CLOUD` off hides the feature in the next build. The worker can
   keep running for existing users through their grace period.

## Open Questions

- Quota and price per tier (placeholder: 250 GB, set in the worker's config). The product id
  is `de.mobilistics.fernsy.cloud.monthly` unless App Store Connect needs otherwise. Neither
  changes the specs or tasks.
