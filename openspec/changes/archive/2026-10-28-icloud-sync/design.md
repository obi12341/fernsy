# Design

## Context

- Per-account values already have a sync-ready shape: `ChannelVisibility` and
  `PinnedCategories` (`FernsyCore/LiveState.swift`) are single Codable values with
  `modifiedAt`, unknown ids kept (hide-live-categories-and-channels design). The Mac stores them
  as files in `Application Support/Fernsy/<account>/`, the Apple TV in UserDefaults per account
  (tvos-library decision).
- Favourites (`library.favorites`) and recently watched (`live.recent`) are UserDefaults
  arrays; resume positions are in `ResumeStore` (FernsyCore); audio/subtitle preferences in
  `TrackPreferences` keys; padding in `Recorder.padBefore/AfterKey`.
- Credentials: `Keychain` (FernsyCore) stores generic passwords under service
  `de.mobilistics.fernsy` (debug: `.dev`): `xtream` (IPTV login), `jellyfin` (session),
  `jellyfin.password`, `mcp.token`. Items are not synchronizable today.
- Identity: universal purchase, the Mac (App Store and Direct/DMG) and Apple TV Release builds
  share `de.mobilistics.fernsy`, debug builds `de.mobilistics.fernsy.dev`, team B8YT7FNB66.

## Goals / Non-Goals

**Goals:**
- One sync layer in FernsyCore used by both apps.
- No server of our own; data stays in the user's iCloud.
- Values keep working offline; sync is an addition, not a dependency.

**Non-Goals:**
- Real-time merging of sets element by element.
- Syncing anything the Jellyfin server already keeps.

## Decisions

### A. Choices in iCloud key-value storage

`NSUbiquitousKeyValueStore` with the default store of the app id, so Mac and Apple TV of one
Apple ID share it and debug builds (other bundle id) stay apart. One key per value:
`acct.<accountKey>.visibility`, `.pinned`, `.favorites`, `.recent`, `.resume`, and
`app.tracks`, `app.padding`. Each value is the existing Codable type wrapped with `modifiedAt`
(favourites, recent, resume and the app values get it). A `SyncStore` in FernsyCore:
- on a local change: write locally as today, then to the store (if the switch is on);
- on `didChangeExternallyNotification` and at launch: for each key, take the remote value if
  its `modifiedAt` is newer than the local one, write it locally and publish it to the model;
- the local copy remains the source the app reads, so turning sync off or losing iCloud
  changes nothing visible.

Sizes: visibility ~10 KB for 1000 ids, resume positions a few KB; far below the store's 1 MB
and 1024 keys for several accounts. Resume entries older than 90 days are dropped from the
synced value (not locally) to stay small.

Rejected:
- **CloudKit for the choices**: records, zones, subscriptions and conflict handling for a few
  small values; the key-value store is made for this and delivers changes by itself.
- **Merging sets element by element**: needs tombstones per id to tell "unhidden" from "never
  hidden"; last change per value is predictable and matches how people use it (one device at a
  time). Recorded as a known limit: two devices changing the same value offline keep the newer
  one whole.
- **Syncing the files/UserDefaults directly (iCloud Drive)**: needs iCloud Drive on and file
  coordination; tvOS has no iCloud Drive documents for apps.

### B. Credentials in CloudKit, encrypted fields

Result of the spike (task 1.1, 2026-10-28, Mac dev build and "Apple TV WZ", same Apple ID):
iCloud Keychain does not reach tvOS. Synchronizable items written on either side never
arrived on the other in ten minutes; Apple documents that tvOS accepts
`kSecAttrSynchronizable` but does not sync app items. A record in the private CloudKit database
of container `iCloud.de.mobilistics.fernsy.dev` with the secret in `encryptedValues` (end-to-end
encrypted) was saved by both and read and decrypted by the other within seconds. The key-value
store (A) also synced both ways within 2–3 s (task 1.2); `ubiquityIdentityToken` is nil on
tvOS (no iCloud Drive) and is no sign of a missing account there, so availability uses
`CKContainer.accountStatus()` instead.

So the logins go to CloudKit: one record per login (`xtream`, `jellyfin.login`) in the private
database, the password and the full credentials in `encryptedValues`, server and user also in
plain fields only where a list needs them (none so far). The keychain stays the device's own
store; the welcome screen offers a CloudKit login that the device has no local copy of. What
follows below for the keychain items' names and the local "signed out here" flag still
applies; "synchronizable" is replaced by "also saved to CloudKit".

Superseded plan (kept for the record):

The `xtream` and `jellyfin.password` items, plus a new `jellyfin.server` item (server URL and
user, without the session), are written with `kSecAttrSynchronizable = true` and
`kSecUseDataProtectionKeychain` on the Mac, in the default access group of the shared app id.
`jellyfin` (session with device token) and `mcp.token` stay device-only. On a device without
an account, a synchronizable `xtream` item is offered on the welcome screen; taking it over
signs in as usual (the device then also has it locally). Jellyfin takeover signs in with the
synced server, user and password and gets its own session.

Signing out deletes only the device's session state and, for the IPTV login, marks it as not
used on this device (a local flag), so the synced item stays and the other devices stay signed
in. "Zugangsdaten abgleichen" off: new and changed logins are written non-synchronizable; the
existing synced item is left alone.

Rejected:
- **Passwords in the key-value store**: not meant for secrets; iCloud Keychain is end-to-end
  encrypted.
- **CloudKit `encryptedValues`**: first rejected as more moving parts; chosen after the spike.
- **Syncing the Jellyfin session**: tokens are per device on the server; sharing one would
  sign the other device out (jellyfin-test-device memory, device id decision in tvos-library).

### A2. As built (tasks 2.1–2.3)

- `SyncStore` (FernsyCore) keeps the stamp of each UserDefaults value itself
  (`sync.t.<key>`), so favourites, recently watched, track languages and padding keep their
  stored form; a value from before sync existed is sent once, stamped then. Favourites and
  recently watched are app-wide values on both apps today, so they sync as app values, not per
  account (their ids are the provider's, so one provider per person is what this serves).
- Resume positions and watched marks sync as one entry `resume`, merged per item by date;
  a finished item beats a position from a device that has not seen it finish; entries older
  than 90 days stay local.
- `LoginSync` (FernsyCore) saves logins to CloudKit behind a small protocol (tests use a fake).
  The planned local "signed out here" flag is not needed: synced logins are only offered on a
  device without an account, never used without a click.
- Keychain-less runs (UI tests, `FERNSY_NO_KEYCHAIN`) sync nothing, so tests never touch the
  developer's iCloud.

### C. Switches

Two settings, both on by default: "Mit iCloud abgleichen" (choices) and "Zugangsdaten
abgleichen" (logins). Off by default was rejected: the point is that a new Apple TV just
works; the data stays in the user's own iCloud. The settings show "iCloud nicht verfügbar"
when `FileManager.default.ubiquityIdentityToken` is nil.

## Risks / Trade-offs

- [iCloud Keychain on tvOS] → checked (task 1.1): it does not sync to tvOS; CloudKit
  `encryptedValues` does, so logins use CloudKit (decision B).
- [Developer ID (Direct) build and iCloud] → checked (task 1.2, 2026-10-28): an archive of
  "Fernsy Direct" (dev bundle id for the test) exported with method `developer-id` and
  automatic signing made Xcode create "Mac Team Direct Provisioning Profile" with iCloud; the
  Developer ID-signed app read the Apple TV's key-value value at once and saved to CloudKit.
  Its CloudKit environment is Production (`icloud-container-environment`), debug builds use
  Development: they do not see each other's records, release builds on all platforms do.
  `scripts/build-dmg.sh` signs without a profile today; it has to archive and export this way
  (or embed the profile) once the entitlements are in, and CI needs the profile or API access
  for automatic signing.
- [CloudKit schema] → Record types are created in the Development environment on first save
  and must be deployed to Production in the CloudKit console before a release uses them.
- [Provisioning] → The app id needs the iCloud capability (key-value storage) and keychain
  sharing in the developer portal; the CI signing for the App Store upload already has
  problems (certificate limit) to clear first.
- [Two devices, single-stream account] → Sync never starts playback or recordings; it only
  moves choices.
- [Values written by an older app version] → The wrapped values carry `version`; unknown
  newer versions are ignored and not overwritten.
