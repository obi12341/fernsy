# Tasks

## 1. Spikes (real devices; stop and report if one fails)

- [x] 1.1 iCloud Keychain on tvOS: a synchronizable generic password written by the Mac dev build appears on the Apple TV dev build (same Apple ID, real Apple TV "Apple TV WZ"); record the result in design.md, switch to CloudKit `encryptedValues` for credentials if not.
- [x] 1.2 Key-value store: a value written by the Mac dev build arrives on the Apple TV dev build and back while both run; check the Developer ID (Direct) build gets the store; record in design.md.
- [x] 1.3 Enable iCloud (key-value storage and CloudKit, containers `iCloud.de.mobilistics.fernsy` and `.dev`) for both app ids in the developer portal and the entitlements (App Store, Direct, Apple TV; Release and dev ids); debug builds signed with a development profile instead of ad hoc; `scripts/build-dmg.sh` and CI export the Direct build with its Developer ID profile (design risks). Dev id and its Developer ID profile done by Xcode during the spikes.

## 2. FernsyCore

- [x] 2.1 `SyncStore`: keys per account and app, `modifiedAt` wrapper with version, newer-wins merge, external-change notification, switch on/off, availability; unit tests with a fake store (newer wins, older ignored, unknown version ignored, offline queue catches up).
- [x] 2.2 Wrap favourites, recently watched, resume positions (90-day trim for the synced copy), track preferences and padding with `modifiedAt`; migrate existing local values (keep them, timestamp "now" only on first sync).
- [x] 2.3 Logins in CloudKit (design B): `xtream` and `jellyfin.login` records in the private database of `iCloud.de.mobilistics.fernsy[.dev]` with the secret in `encryptedValues`; `jellyfin` session and `mcp.token` stay device-only; local "signed out here" flag; availability from `accountStatus()`; tests with a fake store.

## 3. Mac app

- [x] 3.1 `AppModel` reads and writes visibility, favourites, recent, resume, tracks and padding through `SyncStore`; remote changes update the UI live.
- [x] 3.2 Settings: "Mit iCloud abgleichen", "Zugangsdaten abgleichen", availability line; German strings.
- [x] 3.3 First launch without an account offers synced logins.

## 4. Apple TV app

- [x] 4.1 `TVModel` uses `SyncStore` for visibility, pinned, favourites, recent, resume, tracks and padding.
- [x] 4.2 Welcome screen offers synced provider and Jellyfin logins ("Übernehmen").
- [x] 4.3 Settings › iCloud with both switches and availability; German strings.

## 5. Verification

- [x] 5.1 Unit tests green (`scripts/test.sh`, incl. tvOS simulator).
- [x] 5.2 Two dev builds (Mac and Apple TV WZ, same Apple ID, demo server): hide a category on the Mac → gone on the Apple TV; favourite on the Apple TV → on the Mac; padding and audio language both ways; sync switch off stops it.
- [ ] 5.3 Takeover: Apple TV dev build without account offers the Mac's demo login and signs in; signing out on the Apple TV keeps the Mac signed in; Jellyfin takeover with the local test server shows two devices on the server.
- [x] 5.4 iCloud signed out on the simulator: settings say so, the app works locally.
- [x] 5.5 Update DEVELOPMENT.md (capabilities, how to test sync) and the README product page (one line on iCloud).

## Workflow follow-up

- The user checks with the Release builds (App Store or TestFlight) on their own devices once uploads work again.
- Archive with `/opsx:archive`, merge into `main`, push.
