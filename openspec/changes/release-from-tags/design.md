# Design

## Context

`.github/workflows/release.yml` (merged on main with `website-redesign-and-dmg-release`) has
one `dmg` job on the `xcode-27` runner. The job:
1. checks the secrets;
2. selects Xcode 27.1;
3. checks that the tag equals `v$MARKETING_VERSION`;
4. takes FFmpeg from the cache or builds it;
5. imports the Developer ID certificate into a temporary keychain;
6. runs `scripts/build-dmg.sh` (notarization with the API key);
7. verifies the result;
8. uploads the DMG as an artifact for a manual run, or creates the release with
   `gh release create` for a tag.

Version and build number come from the project. `Config/Info.plist` has no version keys;
Xcode generates them from the build settings `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION`. Passing those settings to `xcodebuild` is therefore enough, and the
project file stays untouched.

`scripts/build-appstore.sh` archives with automatic signing (`-allowProvisioningUpdates`,
using the Xcode account on the user's Mac). It exports with `Config/ExportOptions-AppStore.plist`
(`app-store-connect`, destination `export` or `upload`) and raises the build number in the
project with `set-version.sh`.

**Constraints:**
- 1.0 is in App Store review as build 13. 1.1 is submitted only after that approval. Nightlies
  never touch App Store Connect.
- The API key in the secrets has the "Developer" role, which is enough for notarization.
- main currently has 52 commits.

## Goals / Non-Goals

**Goals:**
- A tag is the only step to a release: version, DMG and App Store upload.
- A trusted (notarized) test build of main, at most a day old.
- No version edits in the repo for a release; the build number always rises.

**Non-Goals:**
- Automatic review submission.
- TestFlight distribution.
- An in-app updater.
- Parallel installation of nightly and release.

## Decisions

### 1. Version from the tag, build number from git, both as build settings

A `prepare` job computes:
- **version:** for a tag, the tag without the `v` (it must match `^v[0-9]+\.[0-9]+(\.[0-9]+)?$`).
  A nightly has no release version. It gets `nightly-<commit date in UTC>`, so it never looks
  like a published version. The app only shows the value (About, start log, Jellyfin client
  header), nothing parses it, and outside the App Store any string is allowed.
- **build:** `git rev-list --count <sha>`. Checkout uses `fetch-depth: 0`.

`build-dmg.sh` and `build-appstore.sh` take `BUILD_VERSION` and `BUILD_NUMBER` and pass them as
`MARKETING_VERSION=…` and `CURRENT_PROJECT_VERSION=…` to `xcodebuild`. `build-appstore.sh`
skips its own bump when `BUILD_NUMBER` is given.

A tag must be on main: `git merge-base --is-ancestor <sha> origin/main`. Otherwise the run
fails before building.

The existing check "tag = MARKETING_VERSION" goes away.

Rejected:
- **Writing the version back into the repo from CI:** it needs a bot commit after every
  release, and it would break the tagged commit's reproducibility.
- **`github.run_number` as the build number:** it restarts with a new workflow file, and it is
  shared by nightly and release runs.

The commit count is reproducible from the commit alone. The only condition is that main is
never rewritten (no force push), which already holds.

### 2. Nightly as one rolling pre-release

Triggers:
- `schedule` at 02:00 UTC;
- `workflow_dispatch` with the input `channel: nightly` (the default).

`prepare` compares main's head with the commit of the tag `nightly`. A scheduled run with no
change stops there; a manual run always builds.

Publishing:
1. `gh release delete nightly --cleanup-tag --yes`, if it exists;
2. `gh release create nightly --prerelease --target <sha> --title "Fernsy Nightly 2026-10-25 (build N)"`
   with `Fernsy-Nightly.dmg`.

The text lists the commit, its date and `git log --oneline <last vX.Y>..<sha>`.

The app is the same as a release: same bundle ID, name and data. A nightly replaces the
installed Fernsy and uses the same sign-in, favourites and recordings. That is what testing
an update needs. Release and nightly cannot run side by side.

Rejected:
- **A separate bundle ID "Fernsy Nightly":** it needs its own keychain entries, its own
  sandbox container and a new sign-in. It does not test the real update path, and its
  entitlements and keychain behaviour could differ from the release.
- **A build on every push:** it gives many notarizations for small commits, and Apple limits
  submissions per day.
- **Only workflow artifacts:** they need a GitHub login, and they expire.

### 3. App Store upload with cloud signing

For tags, an `appstore` job runs next to `dmg`:
1. `xcodebuild archive … -allowProvisioningUpdates -authenticationKeyPath <p8>
   -authenticationKeyID <id> -authenticationKeyIssuerID <issuer>`;
2. `-exportArchive` with destination `upload`, through `build-appstore.sh`, which gets
   `ASC_KEY`, `ASC_KEY_ID` and `ASC_ISSUER` and adds the three authentication flags.

Xcode then uses Apple's cloud-managed distribution certificate and creates or downloads the
App Store profile. There is nothing to import, renew or store as a secret.

Cloud signing requires an API key with the **Admin** role. The user replaces the Developer
key with an Admin key; the same key also notarizes. The secrets `NOTARY_KEY_P8` and
`NOTARY_KEY_ID` are updated; `NOTARY_ISSUER` stays the same.

The upload stops at "uploaded". Submitting with release notes stays in App Store Connect.

Rejected:
- **Apple Distribution certificate, Mac Installer certificate and profile as secrets:** that
  means three more secrets, a yearly renewal and manual profile updates.
- **fastlane:** a whole Ruby toolchain for two `xcodebuild` calls.
- **Automatic submission:** release notes and timing stay the user's decision, especially
  while 1.0 is in review.

### 4. Releases created by hand

`publish` first checks `gh release view "$TAG"`:
- If the release exists, it attaches the DMGs with `gh release upload --clobber`, and title
  and text stay.
- Otherwise it creates the release as today, with the text from `RELEASE_NOTES.md` or the
  default.

The workflow still starts from the tag push. Creating a release with a new tag in the web
interface pushes that tag too.

### 5. Job layout

`prepare` (ubuntu, fast) produces the outputs `channel` (release, nightly or skip), `version`,
`build` and `sha`. Then:
- `dmg` (xcode-27) builds, verifies and uploads the DMG as an artifact between jobs;
- `appstore` (xcode-27, tags only) runs in parallel;
- `publish` (ubuntu) needs `dmg` and, for tags, `appstore`. It creates or updates the release
  or the nightly.

A release is therefore only published when the App Store upload also worked. A failed
upload leaves no half-finished release behind.

Concurrency: the group is `release-${{ github.ref }}`, and the nightly has its own group
without cancellation.

## Risks / Trade-offs

- **[Cloud signing with an API key is new for this project]** → It is first tested with a
  manual run with `channel: appstore-test`, which archives and exports (destination
  `export`) without uploading.
- **[The build number jumps from 13 to over 50]** → App Store Connect only needs it to rise.
  In About Fernsy it shows larger numbers, which is harmless.
- **[Nightly replaces the installed app and its data]** → This is intended and documented. A
  nightly is installed deliberately for testing.
- **[The `nightly` tag moves]** → It is never used as a version. A nightly's version string is
  not numeric, which is fine outside the App Store; LaunchServices tells builds apart by the
  rising build number. Version detection only
  considers `v*` tags.
- **[Pushing a tag before 1.0 is approved]** → It would upload a 1.1 build to App Store
  Connect. That is harmless until it is submitted, but the README warns about it, and the
  first release tag stays the user's step.
