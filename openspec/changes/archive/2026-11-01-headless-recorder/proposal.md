# Proposal

## Why

Recordings only happen while Fernsy runs on a Mac (recordings spec: "Recordings run while the
app runs"); the Apple TV records only while it is awake and the app open, iPhone and iPad do not
record at all. People who want reliable recordings at 20:15 without a Mac running need a recorder
that is always on. A small server in a Docker container — on a NAS, a home server or a Raspberry
Pi — can be that recorder, controlled from the apps the user already has and putting its
recordings into Fernsy Cloud, where every app plays them.

## What Changes

- **Fernsy Server**: a headless recorder as a Docker image (linux/amd64 and linux/arm64) that
  plans and runs recordings for one user's IPTV account and uploads each finished recording,
  end-to-end encrypted, to the user's Fernsy Cloud.
- **Control through its own worker, end-to-end encrypted**: the apps write recording orders,
  sealed with a control key that only the user's devices and the paired server hold, to a small
  new worker (`fernsy-control`) without accounts; the server polls it and writes back what it does
  (scheduled, recording, uploading, done, failed). Every app shows the server's recordings and can
  schedule and cancel them. (CloudKit was the first plan; a spike showed its web access to the
  private database is off for accounts with Advanced Data Protection.)
- **Pairing**: an app pairs a new server once with a code the server shows. Through a short-lived
  mailbox on the control worker the app hands it the control key, the cloud key and the IPTV
  login, sealed to the server's own key; the server keeps them in its volume.
- **Shared Swift core on Linux**: a `FernsyShared` target (Xtream client, recording plan and gaps,
  Fernsy Cloud client and crypto) builds on Linux; the server records by copying the provider's
  MPEG-TS stream to a file (no decoding), with reconnects and gap marks like the apps.
- Requires an active Fernsy Cloud subscription for the uploads; the control worker itself does not
  depend on one.

## Capabilities

### New Capabilities

- `headless-recorder`: the server — image, pairing, orders from the apps, recording, upload,
  status, restarts.

### Modified Capabilities

- `recordings`: the apps can schedule a recording on a paired Fernsy Server and list its
  recordings with their state.
- `recording-cloud`: recordings can come from a Fernsy Server as well as from the Mac.

## Impact

- New: `server/` (Swift package for Linux, Dockerfile, compose example), `control-server/` (the
  control worker, D1), a CI job building and publishing the image (GitHub Container Registry),
  docs.
- FernsyCore: the Linux-buildable part split off as the `FernsyShared` target.
- Apps: the server as a record target in the schedule actions, its recordings in the lists,
  Settings › Fernsy Cloud › Server (pair, state, remove).
- CloudKit schema: one new record type, `ControlKey` (development, then production).
- Fernsy Cloud worker: unchanged API; the server is one more client of the user's account.

## Out of scope

- Streaming from the server to the apps on the local network (recordings go through Fernsy Cloud).
- Several users or several IPTV accounts on one server; several servers per user (one at first).
- A web interface on the server beyond a status page and logs.
- Timeshift, live viewing or transcoding on the server.
- Jellyfin.
