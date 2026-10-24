# Proposal

## Why

Releases are half in the repo and half on the user's Mac.

**Today:**
- The version lives in `MARKETING_VERSION`. The release workflow refuses a tag that does not
  match it, so a new version means: edit the project, commit, then tag.
- The App Store build runs only locally (`UPLOAD=1 scripts/build-appstore.sh`). It needs the
  user's Xcode account, and it raises the build number in the project.
- There is no trusted build for testing between releases. Only manual workflow artifacts
  exist, which need a GitHub login and expire after 90 days.

**What the user wants:** GitHub controls everything. `main` produces a current test build,
and a tag `vX.Y` produces the downloadable DMG and the App Store build for submission.

## What Changes

- **The version comes from the tag.** For `vX.Y`, CI builds with `MARKETING_VERSION=X.Y`,
  passed as a build setting, without editing the project. The repo's `MARKETING_VERSION`
  only serves local builds.
- **The build number comes from git.** It is the number of commits on the built commit
  (`git rev-list --count`). It is unique and always rising on `main`, so App Store Connect
  accepts every upload. CI never writes it back to the repo. The number jumps once, from 13
  to more than 50.
- **Nightly.** Once a night, when `main` has changed since the last nightly, and on demand:
  - a notarized DMG on a rolling pre-release **"Nightly"** (tag `nightly`, moved and
    replaced each time);
  - no release version: version = `nightly-<commit date>` (for example `nightly-2026-10-25`),
    build = commit count;
  - the release text names the commit and the changes since the last release tag.

  GitHub's "latest release" ignores pre-releases, so the website's download stays on the
  last real release.
- **Release from a tag `vX.Y`:**
  - the notarized DMG as release "Fernsy X.Y" (`Fernsy.dmg`, `Fernsy-X.Y.dmg`), as today;
  - **additionally** the App Store archive, signed by Apple's cloud signing through the App
    Store Connect API key and **uploaded** to App Store Connect.

  Submitting for review stays a manual step in App Store Connect.
- **Release in the GitHub web interface.** The workflow also works when the release was
  created by hand with a new tag. It then only attaches the DMGs and keeps the user's text.
- **The local scripts stay** for emergencies. `build-appstore.sh` and `build-dmg.sh` also
  take `BUILD_VERSION`/`BUILD_NUMBER` as build settings, without changing the project.
  `set-version.sh` keeps working.

Out of scope:
- submitting for review automatically;
- TestFlight groups;
- an updater in the app (Sparkle);
- a separate bundle ID for nightlies;
- tags other than `vX.Y` / `vX.Y.Z`.

## Capabilities

### New Capabilities
- (none)

### Modified Capabilities
- `distribution`:
  - "Mac App Store build" gets its build number from git and is uploaded from a tag in CI;
  - new requirements "Versions come from release tags", "Nightly builds" and "App Store upload
    from a release tag".

## Impact

- `.github/workflows/release.yml`:
  - triggers `schedule`, `workflow_dispatch` and tags;
  - version and build number from tag and git (`fetch-depth: 0`);
  - a nightly job with a rolling pre-release;
  - an App Store job (archive with `-allowProvisioningUpdates` and the API key, export with
    destination `upload`);
  - release creation that tolerates an existing release.
- `scripts/build-dmg.sh` and `scripts/build-appstore.sh`: optional `BUILD_VERSION` and
  `BUILD_NUMBER`, plus API-key authentication for `-allowProvisioningUpdates` in CI.
- **Secrets:** the API key needs the **Admin** role for cloud signing (today it is
  Developer). The user creates a new key or changes the role, then updates `NOTARY_KEY_*` or
  adds new secrets.
- README: the release process.
- Depends on `website-redesign-and-dmg-release` (the existing release workflow is on main;
  that change's specs are not archived yet).
