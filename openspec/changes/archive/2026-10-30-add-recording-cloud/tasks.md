# Tasks

## 1. Dev infrastructure and R2 spike

- [x] 1.1 Create, in the user's Cloudflare account (credentials from the user), the R2 bucket `fernsy-cloud-dev`, an R2 S3 API token for that bucket only, and the D1 database `fernsy-cloud-dev`. Verify with a throwaway script in the scratchpad:
  - a multipart upload created by a signed S3 request, two equal 16 MiB+256 B parts PUT through presigned UploadPart URLs plus a short last part, completed by a signed request;
  - a ranged GET through a presigned URL returns exactly the requested bytes.

  Record the outcome in design.md › E.
- [x] 1.2 Write `cloud-server/deploy.sh`, modeled on `demo-server/deploy.sh`. It uploads the modules with the R2, D1 and cron bindings and the secrets, for `fernsy-cloud-dev` (with `DEV_TOKEN`) or `fernsy-cloud` (without it). It also applies `cloud-server/schema.sql`. Verify by deploying the dev worker and getting a 401 from `GET /v1/account` without a token.

## 2. Worker

- [x] 2.1 `cloud-server/sigv4.js`: presigned GET/PUT/UploadPart URLs and signed S3 requests with WebCrypto. Verify with `node --test cloud-server/test/sigv4.test.js` against AWS's published SigV4 test vectors and against the 1.1 run.
- [x] 2.2 `cloud-server/store.js` and `schema.sql`:
  - users and recordings,
  - quota accounting (done plus uploading),
  - grace dates, deletion queries.

  Verify with `node --test` on an in-memory SQLite stand-in for D1, including parallel starts that exceed the quota.
- [x] 2.3 `cloud-server/apple.js`:
  - Sign in with Apple identity token check (Apple JWKS, audience = the three bundle ids, expiry);
  - App Store Server API client (ES256 JWT, subscription status, linking the original transaction id to the first user who presents it);
  - session tokens (HS256, 90 days, renewed on use).

  Verify with `node --test` using generated test keys and recorded API answers. Test cases: forged token, wrong audience, refunded transaction, a transaction already linked to another user.
- [x] 2.4 `cloud-server/worker.js`: the routes in design.md › E, the dev-token path only when `DEV_TOKEN` is set, and logs that hold only ids, sizes, times and outcomes. Verify with `node --test` route tests:
  - over quota;
  - another user's id answers 404;
  - completion larger than stated is deleted;
  - no URL or key text in captured logs.
- [x] 2.5 Notifications route and daily cron:
  - refresh status from Apple;
  - delete users 30 days after `ended_at`;
  - abort uploads older than 7 days.

  Verify with `node --test` using faked time, then on the dev worker: an upload started with `DEV_TOKEN` and left unfinished disappears after a cron run with a test override of 0 days.
- [x] 2.6 `cloud-server/README.md`: the routes, secrets, deploy steps and what the server never sees. Add the `node --test` run to `scripts/test.sh` and CI. Verify that `scripts/test.sh` runs the worker tests.

## 3. FernsyCore: crypto, key and API client

- [x] 3.1 `CloudCrypto`: the `FCR1` header and chunk sealing with file key, index nonce and `isLast` AAD; plaintext offset → chunk → ciphertext range; meta sealing under the account key with key id. Verify with `FernsyCoreTests/CloudCryptoTests`:
  - round trip;
  - reading a range from the middle;
  - a changed byte, swapped chunks and a cut-off last chunk all fail;
  - no plaintext TS sync bytes are visible in the output.
- [x] 3.2 `CloudKeyStore`: keychain plus the CloudKit record `cloud.key` in `encryptedValues`, saved with `ifServerRecordUnchanged`. Only `createIfMissing` makes a key (Mac). There is a locked state when none exists, and `IPTV_CLOUDKEY=local` keeps the key in the keychain only (Debug). Verify with tests on a fake backing, like `LoginSync`'s:
  - two creators race and end with one key;
  - the reader never creates one.
- [x] 3.3 `CloudClient`: session sign-in, account, recordings list, start, parts, complete, urls and delete. It renews on use, reports 401 as signed out, and honors `IPTV_CLOUD` and `IPTV_CLOUDTOKEN` (Debug). Verify with `URLProtocol`-stubbed tests, plus one live test against the dev worker with `IPTV_CLOUD`/`IPTV_CLOUDTOKEN`, skipped when they are unset.
- [x] 3.4 `CloudLibrary`: merges the server list with the decrypted `.meta` objects into cloud recordings (title, channel, times, gaps, size, locked), cached per account. Verify with a test on a stubbed client: a locked list without a key, full details with a key.

## 4. FernsyPlayer: streaming decryption

- [x] 4.1 `CloudByteSource: ByteSource`:
  - range-fetches ciphertext and decrypts;
  - 8-chunk read-ahead and an LRU cache of at most 32 MiB;
  - a fresh URL on 403;
  - "damaged recording" on a tag failure.

  Verify with tests against a local `URLProtocol` stub serving an `FCR1` file made from `demo-server` media: seek to the middle, an expired URL mid-play, a corrupted chunk.
- [x] 4.2 Add a `.cloud` mode to `PlayerEngine` and the cloud cases to resume positions. Verify that an encrypted copy of a demo-server recording plays through `CloudByteSource` with seeking, on the Mac with `IPTV_CLOUD` and `IPTV_CLOUDTOKEN` against the dev worker.

## 5. Mac: account, subscription and upload

- [x] 5.1 Add the Sign in with Apple and In-App Purchase entitlements to the Mac, iOS and tvOS targets. Add the `FERNSY_CLOUD` build setting (default NO), which with `IPTV_CLOUD` gates every cloud UI. Verify that a Release build without the setting shows no cloud UI, and that Debug with `IPTV_CLOUD` shows it.
- [x] 5.2 Add a StoreKit configuration file with the product `de.mobilistics.fernsy.cloud.monthly`, and shared purchase and restore code in FernsyCore. After sign-in it posts the original transaction id from `Transaction.currentEntitlements` to `/v1/subscription`. Verify with a StoreKit test (`SKTestSession`) that a purchase, a restore, an expiry and a refund each end in the matching `GET /v1/account` state on the dev worker. *Covered by cloud-account-from-icloud-key 2.4 (fake `CloudStore`, since `SKTestSession` needs an app host) and its 5.4 on real devices.*
- [x] 5.3 Settings › Aufnahmen › "Upload recordings to Fernsy Cloud" (default off) on the Mac:
  - turning it on asks for the subscription first (buy or restore), then Sign in with Apple once;
  - it stays off if either is cancelled;
  - below the switch: subscription state, storage, end and grace dates, sign out, and the plain-words note about the key.

  All strings in English and German. Verify in a Debug run with `IPTV_CLOUD` and `IPTV_CLOUDTOKEN` that every state shows. Use the dev worker's account override to switch between none, active, ended 10 days ago and locked. Verify also that without a subscription no Sign in with Apple prompt appears anywhere.
- [x] 5.4 Upload queue (design D):
  - parts recomputed from the file;
  - state in Application Support;
  - one upload at a time;
  - resumes after quit and network loss;
  - cancel aborts the upload on the server;
  - refused before start when over quota.

  Verify on the Mac with a recording of a demo-server channel and `IPTV_CLOUD`/`IPTV_CLOUDTOKEN`: quit at about 60 %, reopen, and it continues from about 60 %. A cancel leaves nothing in `GET /v1/recordings`. A quota override of 1 GB refuses a larger recording with the needed and the free size.
- [x] 5.5 Recordings section:
  - while the switch is on, finished recordings are queued automatically and older finished ones offer "Upload to Fernsy Cloud";
  - progress and the cloud mark in the row;
  - cloud-only entries;
  - play, and delete from the cloud with confirmation (the local file stays).

  Verify with a demo-server recording and `IPTV_CLOUD`/`IPTV_CLOUDTOKEN`:
  - a running recording has no upload action;
  - a scheduled recording that finishes is queued, and one that fails without data is not;
  - turning the switch off stops uploading and keeps what is stored;
  - a file moved to the Trash stays playable from the cloud;
  - while `IPTV_MAXCONN=1` holds the only stream for a recording, a cloud recording plays without any connection question.

## 6. iPad and iPhone

- [x] 6.1 Settings › Fernsy Cloud: shown only with an active subscription (or one in its grace period), otherwise the offer to subscribe. Account state, sign out and strings as in 5.3, with Sign in with Apple on first use. Verify in the iPad simulator UI test with `IPTV_CLOUD`/`IPTV_CLOUDTOKEN`/`IPTV_CLOUDKEY=local`.
- [x] 6.2 New Recordings section:
  - shown with an active subscription, first opening asks for Sign in with Apple once;
  - cloud recordings, newest first, with title, channel, time and duration;
  - locked state;
  - play with seeking and resume;
  - delete with confirmation.

  Verify with a new `FernsyiOSUITests/CloudRecordingsUITests`. It uploads a fixture with the dev token, then lists, plays from the middle and deletes. Uses `IPTV_CLOUD`/`IPTV_CLOUDTOKEN`/`IPTV_CLOUDKEY=local`.

## 7. Apple TV

- [x] 7.1 Settings › Fernsy Cloud as in 6.1 (offer without subscription, Sign in with Apple on first use). Verify on the "Claude Apple TV" simulator with `IPTV_CLOUD`/`IPTV_CLOUDTOKEN`/`IPTV_CLOUDKEY=local`.
- [x] 7.2 The Recordings screen lists cloud recordings next to the local ones, with play, seeking, resume, delete and the locked state. The first opening by a subscriber asks for Sign in with Apple once. Verify with a new `FernsyTVUITests/CloudRecordingsUITests`: fixture upload, list, jump to 1:30 in a two-hour fixture within a few seconds, delete. Run it with `DEVICE_NAME="Claude Apple TV" scripts/tv-uitest.sh`.

## 8. Documentation and integration

- [x] 8.1 Add to DEVELOPMENT.md:
  - the switches `FERNSY_CLOUD`, `IPTV_CLOUD`, `IPTV_CLOUDTOKEN` and `IPTV_CLOUDKEY`;
  - the StoreKit configuration;
  - a pointer to `cloud-server/README.md`.

  Verify that the documented commands run as written.
- [x] 8.2 End-to-end check on real devices with Release builds of the dev configuration: Mac, "iPad von Patrick" and "Apple TV WZ" on the same Apple ID, the dev worker, `FERNSY_CLOUD = YES`. Upload a demo-server recording on the Mac. The iPad and the Apple TV then get the key from iCloud without input and stream with seeking. Deleting on the iPad removes it everywhere. The R2 objects show no title or channel text. Only the user can do this check with their Apple ID. *Covered by cloud-account-from-icloud-key 5.4 (production worker instead of dev). R2 objects checked on 2026-10-30: `FCR1`/`FCM1` headers, ciphertext entropy 7.9993 bits/byte, no title or channel text.*
- [x] 8.3 Run `openspec validate --all --strict`, `scripts/test.sh`, and the full Apple TV and iPad UI test runs. All must pass.

## Workflow follow-up

- Archive the change on `change/add-recording-cloud`, then merge into `main` and push (with the user's consent). Cloud stays hidden in releases until `FERNSY_CLOUD = YES`.
- Before launch, outside this change: production bucket, D1 and worker; the App Store Connect product and Server API key; the notification URL; the privacy policy text; the legal review.
