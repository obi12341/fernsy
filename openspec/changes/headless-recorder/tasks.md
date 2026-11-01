# Tasks

Stream tests only against the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`,
demo/demo; `IPTV_MAXCONN=1` for single-stream cases); Fernsy Cloud against the dev worker
(`IPTV_CLOUD=https://fernsy-cloud-dev.mobilistics.workers.dev`, dev token); control against the
dev deployment of `fernsy-control`; the server in Docker on
the test VM or the host, and on a Raspberry Pi for the arm64 check.

## 0. Spike (decides decision 3)

- [x] 0.1 Spike script: web auth token from the app (`CKFetchWebAuthTokenOperation`), private database through CloudKit Web Services - refused for accounts without web access (Advanced Data Protection)
- [x] 0.2 Result in design.md (decision 0); decision 3, pairing, proposal and specs moved to the separate control worker

## 1. Shared core on Linux

- [x] 1.1 Target `FernsyShared` (Xtream, channel names, plan, gaps, cloud crypto and client, log) builds on Linux, CryptoKit through swift-crypto; FernsyCore re-exports it
- [x] 1.2 `FernsySharedTests` run on Linux amd64 and arm64 in CI (`linux` job)

## 2. Control worker

- [x] 2.1 `control-server/`: worker, D1 schema (spaces, items, pairing), items endpoints with write secret, change numbers and tombstones, limits and expiry, pairing mailbox with per-IP limits; tests like `cloud-server/test`
- [x] 2.2 Deploy script and dev deployment (`fernsy-control-dev`)
- [x] 2.3 `FernsyShared`: control key derivations, item sealing, pairing code and tag (PBKDF2: CommonCrypto / CryptoExtras), HPKE sealing to the server's key; tests with fixed vectors on macOS and Linux

## 3. Server

- [x] 3.1 `server/` package: config from the environment, data volume layout, logging without secrets
- [x] 3.2 Recorder: HTTP stream copy to `.ts`, reconnect with backoff, gaps; recording rules from `RecordingPlan` (padding, stream limit, overlaps, handover, missed)
- [x] 3.3 Control client: items with the control key (derive space, write secret, item key), polling with the change number
- [x] 3.4 Pairing: key pair, code, mailbox on the control worker, opening the sealed secrets, wipe on removal
- [x] 3.5 Upload with `CloudClient`/`CloudCrypto` and the Mac's details record; resumable; failure reasons
- [x] 3.6 Status page (paired, last contact, free space, running and next, errors)

## 4. Apps

- [x] 4.1 FernsyCore: control key in iCloud (`ControlKey`, like `CloudKeyStore`), control client for order, state and status items
- [x] 4.2 Settings › Fernsy Cloud › Server on Mac, Apple TV, iOS: pair with the code, state, remove
- [x] 4.3 Scheduling offers the server (default on iPhone and iPad); lists show server orders with state and allow cancelling
- [x] 4.4 Stream limit: running server recordings count as connections in use

## 5. Image and CI

- [x] 5.1 `server/Dockerfile` (static binary, minimal runtime image), `compose.yaml` example
- [ ] 5.2 GitHub Actions: build and push linux/amd64 and linux/arm64 to `ghcr.io/obi12341/fernsy-server` on release tags; a test build on pushes to `server/`
- [ ] 5.3 CloudKit schema: `ControlKey` in development, then production

## 6. Docs and verification

- [x] 6.1 DEVELOPMENT.md › Fernsy Server and the user page `server/README.md`: running the server, pairing, removing, privacy (what the volume holds)
- [x] 6.2 End to end (simulators and the host instead of the test VM, which plays no video): the iPhone pairs the server, it records a demo channel and uploads with the iPhone's cloud key, the Apple TV plays the recording from Fernsy Cloud; the Mac shows the server's orders
- [ ] 6.3 arm64 on a Raspberry Pi 4: start, pair, one recording
- [x] 6.4 `openspec validate --all --strict`
- [ ] 6.5 Production deployment of `fernsy-control` before the apps ship

## Workflow follow-up

- With the release that ships the apps' server UI: a "Fernsy Server" part in README.md and on the
  website (project-readme: the README only names what the current release has).
- Release-note trailers when the apps' server UI ships. Archive, merge into `main` and push with
  the user's consent.
