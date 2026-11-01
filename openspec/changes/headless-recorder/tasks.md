# Tasks

Stream tests only against the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`,
demo/demo; `IPTV_MAXCONN=1` for single-stream cases); Fernsy Cloud against the dev worker
(`IPTV_CLOUD=https://fernsy-cloud-dev.mobilistics.workers.dev`, dev token); the server in Docker on
the test VM or the host, and on a Raspberry Pi for the arm64 check.

## 0. Spike (decides decision 3)

- [ ] 0.1 Swift-on-Linux tool: CloudKit web sign-in for `iCloud.de.mobilistics.fernsy`, custom zone, write/read records, zone changes with a sync token, token lifetime and renewal, `encryptedValues` not readable
- [ ] 0.2 Write the result into design.md; if it fails, revise decision 3 and the specs to the worker fallback before going on

## 1. Shared core on Linux

- [ ] 1.1 FernsyCore builds on Linux (Swift Static Linux SDK, amd64 and arm64): Apple-only files behind `#if canImport`, CryptoKit through swift-crypto
- [ ] 1.2 The FernsyCore tests that cover the shared parts run on Linux in CI

## 2. Server

- [ ] 2.1 `server/` package: config from the environment, data volume layout, logging without secrets
- [ ] 2.2 Recorder: HTTP stream copy to `.ts`, reconnect with backoff, gaps; recording rules from `RecordingPlan` (padding, stream limit, overlaps, handover, missed)
- [ ] 2.3 CloudKit Web Services client: zone, orders, states, status, change polling with sync token
- [ ] 2.4 Pairing: key pair, status page with Apple ID sign-in and code, opening the sealed secrets, wipe on removal
- [ ] 2.5 Upload with `CloudClient`/`CloudCrypto` and the Mac's details record; resumable; failure reasons
- [ ] 2.6 Status page (paired, last contact, free space, running and next, errors)

## 3. Apps

- [ ] 3.1 FernsyCore: order, state and status models with the CloudKit framework; sealing secrets to the server's key
- [ ] 3.2 Settings › Fernsy Cloud › Server on Mac, Apple TV, iOS: pair with the code, state, remove
- [ ] 3.3 Scheduling offers the server (default on iPhone and iPad); lists show server orders with state and allow cancelling
- [ ] 3.4 Stream limit: running server recordings count as connections in use

## 4. Image and CI

- [ ] 4.1 `server/Dockerfile` (static binary, minimal runtime image), `compose.yaml` example
- [ ] 4.2 GitHub Actions: build and push linux/amd64 and linux/arm64 to `ghcr.io/obi12341/fernsy-server` on release tags; a test build on pushes to `server/`
- [ ] 4.3 CloudKit schema: record types in development, then production

## 5. Docs and verification

- [ ] 5.1 DEVELOPMENT.md and a short user page (README section or website): running the server, pairing, removing, privacy (what the volume holds)
- [ ] 5.2 End to end on the test VM: pair from the Mac, schedule on the iPad, the server records a demo channel, the recording plays on the Apple TV from Fernsy Cloud
- [ ] 5.3 arm64 on a Raspberry Pi 4: start, pair, one recording
- [ ] 5.4 `openspec validate --all --strict`

## Workflow follow-up

- Release-note trailers when the apps' server UI ships. Archive, merge into `main` and push with
  the user's consent.
