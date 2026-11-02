# Fernsy Control server

Carries recording orders, their states and the server status between the Fernsy apps and a
Fernsy Server, and pairs a new server (OpenSpec: `headless-recorder`; decisions in
`openspec/changes/*headless-recorder/design.md`, 3 and 4). A Cloudflare Worker with one D1
database. It has **no accounts and no subscription check**: the apps and the paired server share
a control key (synced through iCloud), derive a space id, a write secret and an item key from it,
and store only ciphertext here.

## What the server never sees

- The control key, the item key, and anything readable: channels, titles, times, states.
- The write secret: only its SHA-256.
- The pairing code's secret part: the mailbox is named by the first four characters only.
- What remains visible: space ids, item kinds and ids, sizes, change times, IP addresses (only
  as salted hashes in the counters for the limits). Logs hold routes, outcomes and counts only.

## Routes

Item routes need `Authorization: Space <space id>:<write secret>`: 32 lowercase hex characters
and the secret as base64url (32 bytes). The first request for an unknown space registers it with
the secret's hash; a known space with another secret gets 401. Bodies and answers are JSON. Errors
look like `{"error": "<code>", "message": "…"}`.

| Route | Body → answer |
|---|---|
| `GET /v1/items?since=<n>` | → `{items: [{kind, id, change, updatedAt, data \| deleted: true}], change, more}`; items changed after change number `n`, oldest first, at most 500; with `more` ask again from `change` |
| `PUT /v1/items/:kind/:id` | `{data: base64}` (1–8192 bytes) → `{change}`; `413 too_large`, `413 full` (500 live items) |
| `DELETE /v1/items/:kind/:id` | → `{change}`; the item stays as a tombstone for 30 days |
| `DELETE /v1/space` | → 204; the space and all its items |
| `POST /v1/pairing/:mailbox` | server: `{publicKey, tag, claimHash}` (32-byte base64 key and HMAC, hex SHA-256 of a 32-byte claim secret) → `{expiresAt}` (15 min); `409 taken` |
| `GET /v1/pairing/:mailbox` | app: → `{publicKey, tag, expiresAt}`; `404` unknown or expired |
| `PUT /v1/pairing/:mailbox/message` | app: `{message, tag}` → 204, once; `409 taken` |
| `GET /v1/pairing/:mailbox/message` | server, `Authorization: Claim <secret>`: → `{message: null}` until the app answered, then `{message, tag}` and the mailbox is gone; these polls do not count against the IP limit |
| `DELETE /v1/pairing/:mailbox` | server, with its claim → 204 |

`kind` is lowercase letters and dashes (up to 20), `id` up to 64 of `A–Z a–z 0–9 _ -`, the
mailbox four Crockford base32 characters.

**Limits.** 500 live items of 8 KB per space; 120 requests per space and minute; 10 new spaces
and 30 pairing requests per IP and hour (`429 rate_limited`). The per-space minute limit uses the
Workers Rate Limiting binding `RATE_LIMIT` (approximate, counted per Cloudflare location; without
the binding the worker falls back to the D1 counter); the hourly per-IP limits use the `counters`
table.

**What a request writes (control-fewer-writes).** Reading (`GET /v1/items`) writes nothing:
`used_at` moves at most once a day, after the answer (`waitUntil`), which is enough for the 90-day
idle cleanup. A `PUT` writes the item and the space's change number. A Fernsy Server sends its
status only when it changed and otherwise every 5 minutes, so an idle server costs about
26,000 written rows a month.

**Daily cron (03:41 UTC).** Removes expired mailboxes and counters, tombstones older than 30
days, and spaces (with their items) that had no request for 90 days.

## Deploying and testing

`control-server/deploy.sh` (dev: `fernsy-control-dev`) and `--prod` (`fernsy-control`) need
`CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` (Workers Scripts Write, D1 Write). Tests:
`node --test control-server/test/*.test.js` (Node 24, D1 on `node:sqlite`); `scripts/test.sh`
runs them.
