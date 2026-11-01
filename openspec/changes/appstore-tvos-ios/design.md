## Context

`release.yml`'s `appstore` job runs `scripts/build-appstore.sh` on the `xcode-27` runner: it
archives the `Fernsy` scheme (macOS) with `-allowProvisioningUpdates` and the API key, checks the
six FFmpeg frameworks, and exports with `Config/ExportOptions-AppStore.plist` (`app-store-connect`,
automatic signing, destination `upload` for a release). `publish` waits for `dmg` and, for a
release, for `appstore`.

The Apple TV (`Fernsy TV`, with the `FernsyTopShelf` extension and the App Group
`group.de.mobilistics.fernsy`) and iOS (`Fernsy iOS`) schemes use the same bundle id in Release
and build on CI already (`tests.yml`, simulator only). They were installed on the user's devices
as local Release builds; the TV recipe had to add the CloudKit `Production` environment by hand,
which an App Store export sets by itself. FFmpeg's xcframeworks already contain tvOS and iOS
slices. `Info-TV.plist` and `Info.plist` declare `ITSAppUsesNonExemptEncryption`; `Info-iOS.plist`
does not. `fix/appstore-ci-signing` (not merged yet) adds the development-certificate clean-up
to `build-appstore.sh`; this change builds on it.

## Goals / Non-Goals

**Goals:**
- One tag, three uploads with the same version and build number.
- A failure on one platform is visible and can be rerun without rebuilding the others.

**Non-Goals:**
- TestFlight groups, review submission, store metadata.
- Building the tvOS/iOS store apps outside CI with a different path than the Mac one.

## Decisions

### 1. One script, a platform argument
`build-appstore.sh` gets `PLATFORM=macos|tvos|ios` (default `macos`): scheme, archive
destination (`generic/platform=tvOS`, `generic/platform=iOS`) and the framework check path differ
(`Fernsy.app/Contents/Frameworks` on macOS, `Fernsy.app/Frameworks` on tvOS/iOS; the TV archive
must also contain `PlugIns/FernsyTopShelf.appex`). Export options stay one file: `app-store-connect`
with automatic signing works for all three.
Rejected: separate scripts per platform (three copies of version, auth and upload handling).

### 2. A matrix job per platform, release waits for all
The `appstore` job becomes a matrix (`macos`, `tvos`, `ios`) with `fail-fast: false`; `publish`
requires `needs.appstore.result == 'success'`, which for a matrix means every platform. A failed
platform can be rerun alone ("Re-run failed jobs").
Rejected: one job archiving all three in a row (three times longer, one failure hides the next);
publishing the release when only the Mac upload worked (the release would claim a version the
Apple TV and iOS apps do not have).

### 3. Same build number everywhere
All three use the commit count from `prepare` as `CURRENT_PROJECT_VERSION` and the tag as
`MARKETING_VERSION`, as the Mac build does. App Store Connect keeps build numbers per platform,
so equal numbers do not collide.

### 4. Certificate clean-up once, after all archives
Each matrix job archives on its own fresh runner and creates its own development certificate.
A per-job snapshot and revoke (as `fix/appstore-ci-signing` does for the single Mac job) would
let a job that finishes early revoke the certificate of a job still archiving. So the snapshot is
taken once in a small macOS job before the matrix, and one clean-up job after the matrix
(`if: always()`) revokes every development certificate created since; `build-appstore.sh`
skips its own snapshot/revoke when the workflow says so (`CERT_CLEANUP=workflow`).
Rejected: matching certificates by name or runner (the names Xcode gives API-created
certificates are not documented); a stored development certificate as a secret (needs the user
to export and rotate a .p12, and the API key route then still creates certificates).

### 5. Export compliance for iOS
`Info-iOS.plist` gets `ITSAppUsesNonExemptEncryption = NO`, matching the Mac and TV apps
(HTTPS only, no own encryption beyond the system's).

## Risks / Trade-offs

- [App Store Connect has no tvOS/iOS platform on the record yet] → the upload fails with a clear
  error; the user adds the platforms once (DEVELOPMENT.md), then reruns the failed job.
- [The extension or App Group profile cannot be created through the API key] → shows in the
  `appstore-test` run before any release; fallback is registering the App Group on the app ids
  by hand once.
- [Parallel jobs revoke each other's certificates] → decision 4: one snapshot before and one
  clean-up after all archives; the test run's log lists what was revoked.
- [Longer release runs] → the jobs run in parallel; wall time grows little.

## Migration Plan

Merge after `fix/appstore-ci-signing`. Verify with an `appstore-test` run on the branch (three
exported packages), then a real release tag. Rollback: the matrix back to `macos` only.

## Open Questions

- Whether App Store Connect already lists tvOS and iOS on the Fernsy record (the user checks
  before the first release with this change).
