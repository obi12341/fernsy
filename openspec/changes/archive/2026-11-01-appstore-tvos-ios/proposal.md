# Proposal

## Why

Fernsy is one App Store product for Mac, Apple TV and iPhone/iPad (universal purchase, bundle id
`de.mobilistics.fernsy`), but a release tag only archives and uploads the Mac app. The Apple TV
and iOS builds so far went to devices by hand; they never reach App Store Connect, so they cannot
be tested in TestFlight or submitted. Every release should bring all three platforms, with the
same version and build number.

## What Changes

- A release tag archives the Apple TV app (with its Top Shelf extension) and the iPhone/iPad app
  as well as the Mac app, each with Apple's cloud signing through the API key, and uploads all
  three builds to App Store Connect. Submitting for review stays manual.
- The three App Store builds run as parallel jobs. The GitHub release is published only when the
  DMG and all three uploads succeeded, as it does today for the Mac upload.
- The manual `appstore-test` channel archives and exports all three without uploading.
- `scripts/build-appstore.sh` takes the platform (macOS default, `tvos`, `ios`), checks the
  platform's embedded frameworks, and keeps the certificate clean-up of `fix/appstore-ci-signing`
  for each run.
- The iOS Info.plist declares `ITSAppUsesNonExemptEncryption = NO` like the Mac and TV plists,
  so uploads do not stop at the export compliance question.
- DEVELOPMENT.md describes the three uploads and the one-time App Store Connect steps (adding the
  tvOS and iOS platforms to the app record).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `distribution`: "App Store upload from a release tag" covers the Apple TV and iPhone/iPad
  builds as well, and the release waits for all three uploads.

## Impact

- `.github/workflows/release.yml` (the `appstore` job becomes a matrix over the platforms;
  `publish` needs all of them), `scripts/build-appstore.sh`, `Config/Info-iOS.plist`,
  `DEVELOPMENT.md`.
- App Store Connect: the app record needs the tvOS and iOS platforms (a manual step by the user,
  once); builds then appear per platform under TestFlight.
- CI time: two more archives per release (runs in parallel with the Mac one).

## Out of scope

- Submitting for review, App Store texts, screenshots and "What's New" per platform (manual, as
  today).
- Fernsy Cloud in the store builds (`FERNSY_CLOUD` stays off until its launch).
- Nightly App Store or TestFlight builds; nightlies stay DMG-only.
- The local device recipes for the user's Apple TV and iPad (Release builds installed by hand).
