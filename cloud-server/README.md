# Fernsy Cloud server

Private, end-to-end encrypted storage for recordings (OpenSpec: `cloud-server`,
`recording-cloud`; decisions in `openspec/changes/*add-recording-cloud/design.md` and
`*cloud-account-from-icloud-key/design.md`). A Cloudflare Worker with one R2 bucket and a D1
database. The apps encrypt on the device and upload and stream **ciphertext directly to R2**
with short-lived signed URLs. The worker only knows accounts by a hash of their access secret,
checks subscriptions with Apple, keeps the quota and signs those URLs.

## What the server never sees

- Keys, titles, channel names, program details: everything readable is encrypted in the
  app. A recording is two objects, `u/<userId>/<recordingId>.data` and `.meta`, with
  random ids.
- Accounts: the apps derive an account id (a UUID) and a 32-byte access secret from the
  user's cloud key with HKDF. The server stores the account id and the SHA-256 of the
  secret, never the secret or the key.
- What remains visible: account ids, object sizes, upload times, IP addresses.
- Logs hold only user ids, recording ids, sizes, times and outcomes, never signed URLs,
  secrets or the `Authorization` header.

## Routes

All requests except the notifications need `Authorization: Key <accountId>:<secret>`: the
account id as a lowercase UUID and the access secret as base64url (32 bytes). The first request
with an unknown account id registers it with the secret's hash; a known id with another secret
gets 401. Every such request also takes back a subscription that was bought for this account
(its `appAccountToken`) but is linked elsewhere. On the dev deployment `Authorization: Dev
<DEV_TOKEN>` stands for a fixed dev user whose subscription is active by default. Bodies and answers are JSON in camelCase. Times are ISO-8601 UTC strings
or null. Errors look like `{"error": "<code>", "message": "…"}`.

| Route | Body → answer |
|---|---|
| `POST /v1/apple/notifications` | App Store Server Notifications V2 (`{signedPayload}`) |
| `GET /v1/account` | → `{userId, state: none\|active\|grace\|ended, expiresAt, endedAt, deleteAt, usedBytes, totalBytes}`; `userId` is the account id |
| `DELETE /v1/account` | → 204; deletes all recordings (objects and rows) and the account; its subscriptions stay unlinked, so the same key's next request starts an empty account and takes them back |
| `POST /v1/subscription` | `{originalTransactionId, move?: true}` → account; linked when Apple's `appAccountToken` is this account; `409 other_account` when it is missing or another account's, unless `move` (the previous holder enters its grace period); `503 apple_not_configured` |
| `GET /v1/recordings` | → `{recordings: [{id, dataBytes, metaBytes, completedAt}]}`, finished only, newest first |
| `POST /v1/recordings` | `{dataBytes, metaBytes, partSize}` → `{id, uploadId, partSize, partCount, partURLs: [{number, url}], metaURL}`; `402 no_subscription`; `413 quota` with `neededBytes`, `freeBytes` |
| `POST /v1/recordings/:id/parts` | `{numbers: [int], meta?: true}` (0–50 numbers; empty only with `meta`) → `{partURLs, metaURL?}`; `metaURL` is a fresh PUT for the details of a resumed upload |
| `POST /v1/recordings/:id/complete` | `{parts: [{number, etag}]}` → `{id, dataBytes}`; `413 quota` when larger than stated and over quota (deleted); `400 incomplete` when the `.meta` object is missing |
| `GET /v1/recordings/:id/urls` | → `{dataURL, metaURL, expiresAt}` (6 h, ranges allowed); active or grace only |
| `DELETE /v1/recordings/:id` | → 204; also aborts an unfinished upload |
| `POST /v1/dev/account` | dev only: `{state: none\|active\|ended, endedDaysAgo?, quotaBytes?}` → account |
| `POST /v1/dev/cron` | dev only: `{abandonDays?, graceDays?}` → runs the cleanup now |

How uploads work:
- **Parts.** `partURLs` at start covers only the first 20 parts. The rest comes from `/parts`,
  which also renews expired URLs (valid 1 h). Every part has `partSize` bytes except the last,
  as R2 requires, and `partSize` is at least 5 MiB. The `.meta` object is PUT to `metaURL`
  before `complete`.
- **Daily cron (03:17 UTC).** It aborts uploads older than 7 days, asks Apple about
  subscriptions whose expiry passed without a notification, and deletes everything of users
  30 days after their subscription ended.

## Deployments

| | Worker | R2 bucket and D1 | `DEV_TOKEN` |
|---|---|---|---|
| dev | `fernsy-cloud-dev` (https://fernsy-cloud-dev.mobilistics.workers.dev) | `fernsy-cloud-dev` | yes |
| production | `fernsy-cloud` | `fernsy-cloud` | never |

```sh
CLOUDFLARE_ACCOUNT_ID=… CLOUDFLARE_API_TOKEN=… cloud-server/deploy.sh --new-s3-token   # first dev deploy
CLOUDFLARE_ACCOUNT_ID=… CLOUDFLARE_API_TOKEN=… cloud-server/deploy.sh                  # later dev deploys
CLOUDFLARE_ACCOUNT_ID=… CLOUDFLARE_API_TOKEN=… cloud-server/deploy.sh --prod --new-s3-token
```

What `deploy.sh` does:
- Creates the bucket and D1 if they are missing, applies `schema.sql`, uploads the modules
  with their bindings, sets the cron and enables workers.dev.
- Secrets are set only when given in the environment and kept otherwise.
- On dev, `DEV_TOKEN` is generated on the first deploy and printed once; the apps use it as
  `IPTV_CLOUDTOKEN`.
- `--reset-db` drops the D1 tables before applying `schema.sql` (for schema changes before
  launch; R2 objects stay and have to be removed separately).
- `--new-s3-token` creates an account token that may only read and write items in this one
  bucket. Its id is the S3 access key and the SHA-256 of its value the secret, so the
  deploying token never goes into the worker.

The App Store Server API needs `APPSTORE_KEY` (the `.p8` contents), `APPSTORE_KEY_ID` and
`APPSTORE_ISSUER` from App Store Connect. Without them `/v1/subscription` and the
notifications answer `503 apple_not_configured`. A transaction's bundle id must be one of
`BUNDLE_IDS`, by default `de.mobilistics.fernsy,de.mobilistics.fernsy.dev`.
Other settings in the environment are `QUOTA_BYTES` (default 250 GB), `GRACE_DAYS` (30) and
`PRODUCT_ID` (`de.mobilistics.fernsy.cloud.monthly`).

## Tests

```sh
node --test cloud-server/test/*.test.js     # also part of scripts/test.sh and CI
```

Node 24 built-ins only:
- `node:sqlite` stands in for D1 and an in-memory fake for R2 and its S3 endpoint
  (`test/d1.js`).
- SigV4 is checked against AWS's published examples.
