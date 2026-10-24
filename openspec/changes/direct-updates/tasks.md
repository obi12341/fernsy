# Tasks

## 1. Target and package

- [x] 1.1 Duplicate the "Fernsy" target as "Fernsy Direct":
  - same sources, resources and build phases;
  - product name `Fernsy`, bundle ID `de.mobilistics.fernsy`;
  - the scheme "Fernsy Direct", generated automatically like "Fernsy" (no shared scheme, so Xcode keeps generating both).

  Check that both targets compile (`xcodebuild -scheme Fernsy` and `-scheme "Fernsy Direct"`, Debug).
- [x] 1.2 Add the Swift package Sparkle 2 (pin the current 2.x) to "Fernsy Direct" only. Add `DIRECT_DISTRIBUTION`, `Config/Fernsy-Direct.entitlements` (with the mach-lookup exceptions) and `Config/Info-Direct.plist` with the `SU*` keys (`INFOPLIST_KEY_*` only covers Apple's known keys), with a placeholder `SUPublicEDKey` until 4.1. Check that the App Store target contains no `Sparkle.framework` (`find` in the Release build).

## 2. Updater in the app

- [x] 2.1 Add `Fernsy/App/Updater.swift` (`#if DIRECT_DISTRIBUTION`):
  - `SPUStandardUpdaterController` with `startingUpdater: true`;
  - a delegate with `feedURLString(for:)` (nightly or release from `updates.nightly`);
  - a debug switch `IPTV_UPDATEFEED=<url>` for tests.
- [x] 2.2 Recording protection: `shouldPostponeRelaunchForUpdate` while a recording runs or starts within 30 min, then release when the recorder is free; a note to the user. Add a self-test or debug switch `IPTV_TESTUPDATEHOLD=1` that logs the decision for a scheduled test recording on the demo server.
- [x] 2.3 Menu "Nach Updates suchen …" and the Settings section "Updates" (DMG build only); strings in de and en.

## 3. Builds

- [x] 3.1 `build-dmg.sh` builds the scheme "Fernsy Direct". The smoke test checks that `Sparkle.framework` and its XPC services are in the bundle and signed. `build-appstore.sh` stays on "Fernsy".
- [x] 3.2 `release.yml`:
  - fetch Sparkle's tools (`generate_appcast`, the version pinned to the package);
  - create, sign and attach `appcast.xml` for release and nightly, with secret `SPARKLE_ED_PRIVATE_KEY` and URL prefix;
  - extend the secrets check.

## 4. Key and verification

- [x] 4.1 README: create the key (`generate_keys`), set the secret, enter the public key. The user creates the key and sets the secret; I enter the public key.
- [x] 4.2 Debug build of "Fernsy Direct" against a local test feed (`IPTV_UPDATEFEED` pointing to a feed with a higher build number, served with `python3 -m http.server`). The update window appears with notes. Only when the user is not using Fernsy (demo server, `FERNSY_NO_KEYCHAIN`). Covered by the real update in 4.5 (nightly 66 → 68 through the real feed), which is the stronger test.
- [x] 4.3 `IPTV_TESTUPDATEHOLD` with a running test recording (`IPTV_TESTRECORD`, demo server): the log shows the installation postponed, then released after the recording. Result: "waits for recordings" from the start (recording due within 30 min) through the recording, "would install" from its end on.
- [x] 4.4 CI: a nightly with appcast. `appcast.xml` is on the pre-release, contains build number, signature and DMG URL, and the DMG passes `spctl`. Run `appstore-test`: the App Store package contains no Sparkle.
- [x] 4.5 Manual (the user): install the newest nightly over an older nightly with "Nightly-Builds erhalten" on. The update is offered, installs and relaunches. Keep this task open until the user confirms.
- [x] 4.6 `openspec validate direct-updates --strict` and `openspec validate --specs --strict`.

## Workflow follow-up

- Archive `website-redesign-and-dmg-release` first (its DMG requirement is modified here).
- `/opsx:archive`, then commit, merge into main and push, only after the user agrees.
