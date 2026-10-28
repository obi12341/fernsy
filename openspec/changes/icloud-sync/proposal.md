# Proposal

## Why

The Mac and the Apple TV app are sold together (universal purchase) and often used by the same
person, but every choice has to be made twice: signing in to the provider and Jellyfin, hiding
categories and channels, favourites, audio and subtitle languages, recording padding. Hiding a
category on the Mac should hide it on the Apple TV, and an Apple TV next to a Mac that is
already set up should not need the provider's credentials typed with a remote. The visibility
value was built for this (hide-live-categories-and-channels: one value per account with
`modifiedAt`, "a later sync can store it as one `NSUbiquitousKeyValueStore` entry").

## What Changes

- Settings and per-account choices sync through the user's iCloud between the Mac app and the
  Apple TV app (and between several Macs or Apple TVs): hidden categories and channels,
  favourites, recently watched channels, pinned categories, resume positions of provider films
  and episodes, preferred audio and subtitle languages, recording padding.
- Account credentials sync end-to-end encrypted through the user's iCloud (CloudKit encrypted
  fields; iCloud Keychain does not reach tvOS, see design B): the IPTV login and the Jellyfin server,
  user and password. Each device still signs in to Jellyfin as its own device with its own
  session; sessions and device ids never sync.
- An Apple TV (or Mac) that finds synced credentials offers to use them on first launch
  ("Von deinem Mac übernehmen") instead of the sign-in form.
- A switch "Mit iCloud abgleichen" in the settings of both apps, on by default; credentials
  have their own switch, also on by default. Turning a switch off keeps the local values and
  stops sending and receiving.
- Conflicts: per value, the newer change wins (`modifiedAt`); ids unknown to the current
  catalog are kept, as today.
- Without iCloud (signed out, iCloud Drive off, network down) everything works locally and
  catches up later.

Out of scope:
- Recordings, scheduled recordings (they run only on the device whose app is open, and a
  single-stream account cannot record on two devices), catalog and EPG caches.
- Jellyfin sessions, device ids, watched state and resume positions (Jellyfin keeps those on
  the server already).
- The MCP token, the log, debug switches, window and sort settings, "Erotik anzeigen" (the
  Apple TV keeps adult content hidden by its own rule).
- Syncing debug builds with release builds (debug builds have their own bundle id and stay
  apart).

## Capabilities

### New Capabilities
- `icloud-sync`: what syncs between the user's devices, how conflicts resolve, the switches,
  taking over synced accounts on a new device, and behaviour without iCloud.

### Modified Capabilities
- `apple-tv`: first launch offers synced accounts; Settings gets the iCloud switches.

## Impact

- `FernsyCore`: a sync layer over `NSUbiquitousKeyValueStore` for the per-account values and
  settings (shared by both apps), keychain items marked synchronizable.
- Mac `AppModel`, settings UI; Apple TV `TVModel`, `SettingsScreen`, welcome screen.
- Entitlements: iCloud key-value store for both targets (App Store and Direct builds), keychain
  sharing; App Store Connect/portal capability for the app id; privacy manifest unchanged (no
  new data types leave the user's iCloud).
- German strings; README (product page) gets a line about iCloud sync.
