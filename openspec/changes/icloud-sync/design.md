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

### B. Credentials in iCloud Keychain

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
- **CloudKit `encryptedValues`**: also end-to-end, but more moving parts for two items.
- **Syncing the Jellyfin session**: tokens are per device on the server; sharing one would
  sign the other device out (jellyfin-test-device memory, device id decision in tvos-library).

### C. Switches

Two settings, both on by default: "Mit iCloud abgleichen" (choices) and "Zugangsdaten
abgleichen" (logins). Off by default was rejected: the point is that a new Apple TV just
works; the data stays in the user's own iCloud. The settings show "iCloud nicht verfügbar"
when `FileManager.default.ubiquityIdentityToken` is nil.

## Risks / Trade-offs

- [iCloud Keychain on tvOS] → tvOS supports synchronizable keychain items on paper, but whether
  an Apple TV takes part in iCloud Keychain for third-party items must be checked on the real
  device first (task 1.1). If it does not, the takeover uses CloudKit `encryptedValues` for the
  two credential items instead; the spec stays the same.
- [Developer ID (Direct) build and iCloud] → Developer ID apps get CloudKit; whether the
  key-value store works there must be checked (task 1.2). If not, the Direct build syncs
  nothing and says so in its settings; the App Store builds sync.
- [Provisioning] → The app id needs the iCloud capability (key-value storage) and keychain
  sharing in the developer portal; the CI signing for the App Store upload already has
  problems (certificate limit) to clear first.
- [Two devices, single-stream account] → Sync never starts playback or recordings; it only
  moves choices.
- [Values written by an older app version] → The wrapped values carry `version`; unknown
  newer versions are ignored and not overwritten.
