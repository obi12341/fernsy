## Context

- Recording today: `Recorder` (FernsyPlayer) records through `LiveTuner`/`PlaybackSession`
  (FFmpeg via `CFFShim`, `ObservableObject`), Apple-only. The rules — padding, stream limit,
  overlaps, handover, gaps, missed — live in FernsyCore's `RecordingPlan` and friends.
- FernsyCore imports CloudKit, StoreKit, Security, Network, Observation, CoreGraphics and
  CryptoKit in a few files; most files need only Foundation.
- Fernsy Cloud: the apps encrypt with the user's cloud key (`CloudCrypto`, CryptoKit) and upload
  through `CloudClient` to the worker; the key and the synced logins are stored in the private
  CloudKit database in `encryptedValues` (`CloudKey`, `Login`), end-to-end encrypted by Apple.
- Fernsy Cloud authenticates an account with a secret derived from the cloud key
  (`CloudAccountKey.accessSecret`, `Authorization: Key <account>:<secret>`): whoever holds the
  cloud key can act as the account, and only the user's devices hold it.
- Decided with the user (2026-11-01): Docker image for servers and Raspberry Pi, controlled from
  the apps, recordings go to Fernsy Cloud. Control was planned through CloudKit; the spike
  (decision 0) moved it to its own worker, end-to-end encrypted (decision 3).

## Goals / Non-Goals

**Goals:** recordings that happen without any Apple device running; one control surface (the
apps); no new secrets path through our worker; reuse the apps' recording rules and cloud client.

**Non-Goals:** see proposal (LAN streaming, multi-user, web UI, timeshift, transcoding).

## Decisions

### 0. Spike: CloudKit Web Services against the private database (done, failed)
Tried on 2026-11-01 against `iCloud.de.mobilistics.fernsy.dev` (development) with a curl/Python
script. Results:
- A web auth token needs no browser sign-in: an app gets one with `CKFetchWebAuthTokenOperation`
  (macOS, iOS, tvOS; the token is bound to the API token it was fetched with).
- With that token, the private database answered `403 ACCESS_DENIED` "private db access disabled
  for this account": the account has web access to iCloud data turned off, which is the default
  with Advanced Data Protection. Every user with it would have to turn on web access to all their
  iCloud data for the server - not acceptable, and exactly the users who run a home server.
- The token rotates with every response (`X-Apple-CloudKit-Web-Auth-Token`), so a long-running
  server would have to carry it forward without a gap - another way to break.
So control does not go through CloudKit (decision 3).

### 1. Swift on Linux, sharing a small part of FernsyCore
The server is a Swift package (`server/`) built with the Swift Static Linux SDK (musl) for amd64
and arm64. It shares only what must stay identical to the apps: a new target `FernsyShared` in the
FernsyCore package holds the Xtream client and models, channel names, `RecordingPlan` and
`GapTracker`, `CloudCrypto` and `CloudClient`, the app log and `TestOffline` - Foundation only,
CryptoKit through swift-crypto's `Crypto` (same API) on Linux, no string catalogs on Linux.
FernsyCore depends on it and re-exports it (`@_exported import`), so app code does not change; on
Linux the manifest contains only `FernsyShared` and its tests. Everything else the server needs
(recorder, CloudKit Web Services client, pairing, status page, upload queue) is written for the
server; the apps' `CloudUploadQueue` is tied to CloudKit and StoreKit and is not reused.
Rejected: making all of FernsyCore build on Linux (tried first: `#if canImport` guards in two
dozen files, and every new Apple API in FernsyCore would break the server build again); a rewrite
of the shared parts in the server (two copies of the recording rules and of the crypto, which must
stay byte-compatible with the apps); a rewrite in Go or Node (same, plus a second language);
running the macOS app headless (no Apple hardware on a Pi).

### 2. Recording by copying the stream
Xtream live streams are MPEG-TS over HTTP. The server writes the bytes to `<id>.ts` as they come,
reconnects with backoff when the connection breaks or delivers nothing, and records gaps (start,
length) as the apps do. No decoding, no FFmpeg in the image.
Rejected: FFmpeg remuxing (a Linux FFmpeg build per arch for no gain; the apps' recordings are
`.ts` too); HLS-only providers are out of scope for the first version (logged as unsupported).

### 3. Control through its own worker, end-to-end encrypted, without accounts
A separate Cloudflare worker, `fernsy-control` (`control-server/` in the repository, its own D1
database), carries orders and states between the apps and the server. It has no accounts and does
not know about subscriptions:
- **Control key.** The apps create a random 256-bit control key once and sync it through iCloud
  like the cloud key (record `ControlKey`, `encryptedValues`). From it they derive with HKDF (own
  salts): the space id, a write secret (the worker keeps only its SHA-256, set by the first write)
  and the item key. Whoever holds the control key - the user's devices and the paired server - can
  read and write the space; the worker sees only ids and ciphertext.
- **Items.** `GET /v1/spaces/<space>/items?since=<n>` returns the items changed after change
  number `n` (deleted ones as tombstones); `PUT .../items/<kind>/<id>` writes one, `DELETE` removes
  it; every request carries the write secret. Each item is a JSON body sealed with AES-GCM under
  the item key, the AAD binds kind and id. Kinds and their writers:
  - `order` (apps): channel id and name, show title, start, end, padding, created by, cancelled.
  - `state` (server, same id as its order): scheduled, recording, uploading, done, failed or
    refused with a reason, file size, cloud recording id.
  - `server` (server, one item): last contact, version, free space, running and next orders, error.
  One writer per kind keeps app and server edits from conflicting.
- **Polling.** The server polls every 30 seconds; the apps poll while a recordings list or the
  server settings are open and when they come to the foreground.
- **Limits instead of a subscription.** Per space at most 500 items of 8 KB and 120 requests a
  minute, at most 10 new spaces per IP and hour; deleted items stay as tombstones for 30 days, so
  a device that was away for less than that catches up (one away longer reads from change 0 and
  drops what it no longer finds); spaces without a request for 90 days are
  removed entirely. The worker cannot see when an order ended, so the server deletes done and
  failed orders and their states 30 days after their end. The subscription is checked where it costs: Fernsy Cloud refuses the server's uploads
  without one (headless-recorder spec), so control itself stays free and could later serve a
  server that keeps recordings at home.
Rejected: CloudKit (decision 0); the items as part of the Fernsy Cloud worker (ties control to the
subscription and the cloud account, and mixes a small always-polled store into the storage
worker's deployment); a readable order store (the worker would learn the user's viewing plans);
push to the server (an open connection per server; 30 s polling is cheap and enough).

### 4. Pairing through a short-lived mailbox on the worker
1. The server starts unpaired, creates an X25519 key pair and a pairing code of ten characters
   (Crockford base32, shown as `XXXX-XXXXXX`, about 50 bits). The first four characters are the
   mailbox id, the other six the secret; the worker only ever sees the mailbox id.
2. The server posts its public key, a tag and the hash of a random claim secret to
   `fernsy-control`, `POST /v1/pairing/<mailbox>` (30 pairing requests per IP and hour; expires
   after 15 minutes; a taken mailbox makes the server pick a new code). The tag is an HMAC of the public key under a key
   derived from the secret with PBKDF2-SHA256 (600,000 rounds; CommonCrypto on Apple platforms,
   swift-crypto `CryptoExtras` on Linux, so the apps link no BoringSSL), so
   a worker that wanted to swap the key would have to guess the secret offline faster than the
   mailbox expires.
3. The user enters the code in the app (Settings › Fernsy Cloud › Server). The app fetches the
   public key, checks the tag, and puts a sealed message into the mailbox: the control key, the
   cloud key and the chosen IPTV login, sealed to the server's key with HPKE (RFC 9180,
   X25519 / HKDF-SHA256 / ChaCha20-Poly1305, in CryptoKit and swift-crypto), with an HMAC under the same code-derived key, so that someone who guessed the mailbox
   cannot hand the server their own account.
4. The server polls its mailbox with its claim secret (only it can pick the message up), opens
   the message, stores the secrets in its volume (file mode 600); picking it up closes the
   mailbox. From then on it reads and writes the control space and uploads to
   Fernsy Cloud with the cloud key's access secret, like the Mac; it writes its `server` item and
   the app shows it as paired.
5. Removing the server in the app writes a `removed` mark into the space and deletes the `server`
   item; the server sees it on its next poll, wipes its secrets and shows a new code.
Rejected: the user types the IPTV password and cloud key into the server's page (the cloud key
is not something users see); a QR code (Apple TV and Mac have no camera); pairing over the local
network (needs the local network permission in every app and fails when the phone is not at
home); CloudKit records for pairing (decision 0).

### 5. Stream limit across server and apps
The server counts its own running recordings against the account's limit (from the provider's
`max_connections`) and refuses orders that would exceed it. The apps read the server's `server`
item and the order states and count the server's running recordings as connections in use: when
playing a channel would exceed the limit, they ask first ("Watch Anyway" / "Cancel"). Unlike a
recording on the device itself, the server's recording is not stopped from the app (that would
lose it); the provider then decides which stream it cuts, and the server marks a gap and
reconnects. A server that has not reported for 10 minutes does not count.

### 6. Upload
After a recording ends (and its handover window), the server encrypts and uploads it with the
shared `CloudClient`/`CloudCrypto` and the same details record the Mac writes (title, channel,
times, gaps), resumable as on the Mac. The local file is deleted after the worker confirms. A full
quota or an ended subscription fails the order with that reason and keeps the file for 7 days.

### 7. Image and distribution
`server/Dockerfile` builds the static binary in a Swift builder stage and copies it into a minimal
runtime image (distroless static or `scratch` plus CA certificates and tzdata). A GitHub Actions job
builds linux/amd64 and linux/arm64 with buildx and pushes to `ghcr.io/obi12341/fernsy-server` on
release tags. Configuration by environment: `TZ`, `FERNSY_DATA=/data`, `FERNSY_PORT` (status page,
default 8080). A `compose.yaml` example in the docs. The image falls under the repository license
(PolyForm Noncommercial).

## Risks / Trade-offs

- [The worker could swap the server's key during pairing] → the PBKDF2 tag (decision 4); the
  attacker would be our own worker, and the window is 15 minutes.
- [Polling costs worker requests] → one request per server every 30 s (~86,000 a month), well
  inside the Workers plan; apps poll only while the relevant screens are open.
- [A free, account-less store invites misuse] → small per-space limits, per-IP limits on space
  creation and pairing, expiry of idle spaces; a space only holds ciphertext of its owner.
- [A second worker to run] → same Cloudflare account and deploy script pattern as Fernsy Cloud,
  its own dev deployment for tests.
- [The status page is plain HTTP in the LAN] → it shows the pairing code and state only, no
  secrets; docs warn against exposing the port.
- [The server's volume holds the cloud key and the IPTV login] → file mode 600, never logged;
  removing the server in the app wipes them; documented. Whoever takes the volume can act as the
  account until the user removes the server.
- [Provider counts the server's connection when the user also watches] → decision 5; with a
  single-stream account the server's recording wins and the apps ask before taking it.
- [Clock and time zone on small devices] → `TZ` required in the docs; orders carry absolute times.
- [Raspberry Pi SD cards wear and fill] → recordings are deleted after upload; free space in status.

## Migration Plan

New component; nothing changes for users without a server. `fernsy-control` is deployed (dev
first, then production) before the apps that use it; the `ControlKey` record type goes to the
CloudKit schema (development, then production). The image ships with the app release that adds the pairing UI.

## Open Questions

- Whether the Apple TV's own recordings and the server's should be merged into one list (first
  version: one list with a "Server" mark).
- CloudyKit (github.com/camdenfullmer/CloudyKit, MIT) was looked at during the spike: CloudKit API
  over Web Services, public database with server-to-server keys only - moot now.
