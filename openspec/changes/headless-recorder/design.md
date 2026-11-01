## Context

- Recording today: `Recorder` (FernsyPlayer) records through `LiveTuner`/`PlaybackSession`
  (FFmpeg via `CFFShim`, `ObservableObject`), Apple-only. The rules — padding, stream limit,
  overlaps, handover, gaps, missed — live in FernsyCore's `RecordingPlan` and friends.
- FernsyCore imports CloudKit, StoreKit, Security, Network, Observation, CoreGraphics and
  CryptoKit in a few files; most files need only Foundation.
- Fernsy Cloud: the apps encrypt with the user's cloud key (`CloudCrypto`, CryptoKit) and upload
  through `CloudClient` to the worker; the key and the synced logins are stored in the private
  CloudKit database in `encryptedValues` (`CloudKey`, `Login`), end-to-end encrypted by Apple.
- Decided with the user (2026-11-01): Docker image for servers and Raspberry Pi, controlled from
  the apps through CloudKit, recordings go to Fernsy Cloud.

## Goals / Non-Goals

**Goals:** recordings that happen without any Apple device running; one control surface (the
apps); no new secrets path through our worker; reuse the apps' recording rules and cloud client.

**Non-Goals:** see proposal (LAN streaming, multi-user, web UI, timeshift, transcoding).

## Decisions

### 0. Spike first: CloudKit Web Services against the private database
Before anything else, a throwaway script (curl against CloudKit Web Services; the language does
not matter for what it has to prove) shows: (a) signing in once with the user's
Apple ID through CloudKit's web sign-in yields a `ckWebAuthToken` for the private database of
`iCloud.de.mobilistics.fernsy`; (b) with it the tool can create a custom zone, write and read
plain records and fetch zone changes with a sync token; (c) how long the token lives and how it
renews; (d) that `encryptedValues` fields are indeed not readable (expected). If (a)–(c) fail,
control moves to the Fernsy Cloud worker (rejected alternative below) and the specs are revised
before building.

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

### 3. Control through the user's private CloudKit database
A custom zone `FernsyServer` holds three record types: `RecordingOrder` (written by the apps:
channel id and name, show title, start, end, padding, created by), `RecordingState` (written by the
server, same record name as its order: state, reason, file size, upload id), `FernsyServerStatus`
(written by the server: last contact, version, free space, running and next orders, error). The
server polls zone changes every 30 seconds with a sync token (CloudKit Web Services offers no push
to servers). The apps use the CloudKit framework as for the other synced data. Two record types
for one order keep writers apart: no conflicts between app and server edits.
Rejected: control through the Fernsy Cloud worker (works without Apple's web sign-in, but adds a
second sync path and makes the worker see readable orders; it is the fallback if the spike fails);
one record type written by both (CloudKit conflicts on every state change).

### 4. Pairing
1. The server starts unpaired, creates an X25519 key pair and serves a status page on its port.
2. On the page the user signs in with their Apple ID (CloudKit web sign-in); the server stores the
   web token in its volume and writes a `FernsyServerPairing` record: its public key and a
   six-digit code shown on the page.
3. The app (Settings › Fernsy Cloud › Server) sees the pairing record, asks for the code shown by
   the server and, when it matches, writes `FernsyServerSecrets`: the cloud key and the chosen IPTV
   login, sealed to the server's public key (HPKE-style: X25519 + HKDF + AES-GCM). CloudKit only
   carries ciphertext; `encryptedValues` are not needed.
4. The server opens the secrets, stores them in its volume (file mode 600) and deletes the secrets
   record. Removing the server in the app deletes the pairing; the server notices, wipes its
   secrets and shows a new code.
Rejected: typing the IPTV password and cloud key into the server's page (the cloud key is not
something users see); a QR code from the server read by the iPhone (Apple TV and Mac have no
camera, and the code already proves it is the right server).

### 5. Stream limit across server and apps
The server counts its own running recordings against the account's limit (from the provider's
`max_connections`) and refuses orders that would exceed it. The apps read the server's status and
count its running recordings as connections in use, so "Ask before taking a connection" (recordings
spec) also covers the server.

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

- [CloudKit web sign-in or token renewal does not work for a long-running server] → spike first
  (decision 0); fallback: control through the worker.
- [Apple ID sign-in on a page served over plain HTTP in the LAN] → the sign-in itself happens on
  Apple's pages; the server only receives the token. The status page binds to the LAN; docs warn
  against exposing it.
- [The server's volume holds the cloud key and the IPTV login] → file mode 600, never logged;
  removing the server in the app wipes them; documented.
- [Provider counts the server's connection when the user also watches] → decision 5; with a
  single-stream account the server's recording wins and the apps ask before taking it.
- [Clock and time zone on small devices] → `TZ` required in the docs; orders carry absolute times.
- [Raspberry Pi SD cards wear and fill] → recordings are deleted after upload; free space in status.

## Migration Plan

New component; nothing changes for users without a server. CloudKit record types go to the
development schema first, then production before release. The image ships with the app release
that adds the pairing UI.

## Open Questions

- Results of the spike (decision 0) decide between CloudKit and the worker fallback.
- CloudyKit (github.com/camdenfullmer/CloudyKit, MIT) offers the CloudKit API over Web Services but
  only with server-to-server keys for the public database, without the private database and zone
  changes this design needs; at most a reference for request shapes.
- Whether the Apple TV's own recordings and the server's should be merged into one list (first
  version: one list with a "Server" mark).
