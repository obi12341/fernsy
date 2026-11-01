# Tasks

This change starts from `fix/appstore-ci-signing` (certificate clean-up) and is merged after it.
It changes no app behavior, so no demo-server run or `IPTV_*` switch is involved; verification is
CI runs: `appstore-test` on the branch and the next release tag.

## 1. Script

- [x] 1.1 `scripts/build-appstore.sh`: `PLATFORM=macos|tvos|ios` (default `macos`) picks the scheme (`Fernsy`, `Fernsy TV`, `Fernsy iOS`), the archive destination (`generic/platform=tvOS`, `generic/platform=iOS`) and the output folder (`build/appstore/<platform>`)
- [x] 1.2 Framework check per platform: `Contents/Frameworks` on macOS, `Frameworks` on tvOS/iOS (six FFmpeg frameworks, no loose dylibs); the tvOS archive must contain `PlugIns/FernsyTopShelf.appex`
- [x] 1.3 `CERT_CLEANUP=workflow` skips the script's own certificate snapshot and revoke (the workflow does it once, design 4)
- [x] 1.4 `Config/Info-iOS.plist`: `ITSAppUsesNonExemptEncryption = NO`

## 2. Workflow

- [x] 2.1 A `certs-snapshot` job (macOS) before the App Store jobs stores the development certificate ids as an artifact
- [x] 2.2 `appstore` becomes a matrix over `macos`, `tvos`, `ios` (`fail-fast: false`), each with `PLATFORM` and `CERT_CLEANUP=workflow`; a test run checks each exported package's signature
- [x] 2.3 A `certs-cleanup` job after the matrix (`if: always()`, when the snapshot exists) revokes the certificates created since the snapshot
- [x] 2.4 `publish` still requires `needs.appstore.result == 'success'` for a release, which now means all three platforms

## 3. Docs

- [x] 3.1 DEVELOPMENT.md › Releases: three uploads per tag, rerunning one failed platform, the one-time App Store Connect step (add the tvOS and iOS platforms to the Fernsy record), and the certificate clean-up jobs

## 4. Verify

- [ ] 4.1 The user confirms App Store Connect lists macOS, tvOS and iOS on the Fernsy record (or adds them)
- [ ] 4.2 `release.yml` run with `-f channel=appstore-test` on the branch: three exported packages, `pkgutil`/`codesign` checks pass, the clean-up job revokes only the run's certificates (log)
- [x] 4.3 `openspec validate --all --strict` passes

## Workflow follow-up

- Archive on `change/appstore-tvos-ios`, merge into `main` and push with the user's consent. The
  next release tag (after the user's go) is the first with all three uploads; its builds appear
  in App Store Connect › TestFlight per platform. No release-note trailers: nothing in the apps
  changes.
