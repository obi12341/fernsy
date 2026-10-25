# distribution Specification

## Purpose
How Fernsy is built and shipped: the Mac App Store build, the DMG for direct installation,
and the licensing obligations of the bundled third-party code.

## Requirements

### Requirement: Mac App Store build
The App Store build SHALL be sandboxed (network client only, plus what features add), arm64
only, signed with automatic signing for team B8YT7FNB66, declare no non-exempt encryption,
include a privacy manifest, and get a new build number for every upload. In CI the build
number SHALL be the commit count of the built commit; locally the script still raises it in
the project.

#### Scenario: Uploading a build
- **WHEN** `UPLOAD=1 scripts/build-appstore.sh` runs
- **THEN** the build number is incremented, the archive is exported and uploaded to App Store Connect

#### Scenario: Build number in CI
- **WHEN** CI builds commit number 214 on main
- **THEN** the app's build number is 214 and the project file is not changed

### Requirement: DMG for direct installation
`scripts/build-dmg.sh` SHALL build the "Fernsy Direct" variant (with the updater) and produce
`dist/Fernsy-<version>.dmg`, ad-hoc signed by default or with a given identity (optionally
notarized, with a keychain profile or an App Store Connect API key), after a launch smoke test
that loads the FFmpeg libraries from the bundle only.

#### Scenario: Local test build
- **WHEN** the script runs with `SIGN_IDENTITY="Apple Development: …"`
- **THEN** the DMG contains an app whose keychain access survives rebuilds

#### Scenario: Notarizing with an API key
- **WHEN** the script runs with a Developer ID identity and `NOTARY_KEY`, `NOTARY_KEY_ID` and `NOTARY_ISSUER`
- **THEN** the DMG is notarized and stapled

### Requirement: LGPL-only FFmpeg
Bundled FFmpeg SHALL be built from source without GPL or nonfree components and without
encoders, as shared libraries inside the app; the credits SHALL name FFmpeg, the LGPL and
the exact source archive.

#### Scenario: Building FFmpeg
- **WHEN** `scripts/build-ffmpeg.sh` runs
- **THEN** it refuses to finish if the configuration enables GPL or nonfree code

### Requirement: Store texts within limits
Store texts (name, subtitle, promotional text, description, keywords, what's new) SHALL be
kept locally in `docs/app-store.md` (git-ignored, not published) in German and English and
stay within App Store Connect limits.

#### Scenario: Checking texts
- **WHEN** `python3 scripts/check-store-texts.py` runs
- **THEN** every field is reported within its character limit

### Requirement: Release build in GitHub Actions
A GitHub Action SHALL, on a `v*` tag, build FFmpeg (LGPL, cached), build the app signed with
Developer ID and hardened runtime, run the smoke test, notarize and staple the DMG, and attach
it to a GitHub release as `Fernsy.dmg` and `Fernsy-<version>.dmg`, with German and English
notes from the `Release-Note-de`/`-en` commit trailers since the previous release tag. Run
manually, it SHALL build the same DMG as a workflow artifact. Signing data SHALL come only
from repository secrets.

#### Scenario: Tagging a release
- **WHEN** the tag `v1.1` is pushed on main
- **THEN** a release "Fernsy 1.1" appears with a notarized `Fernsy.dmg` that opens on another Mac without a Gatekeeper warning

#### Scenario: Missing secrets
- **WHEN** the Action runs without the signing secrets
- **THEN** it fails before building with a message naming the missing secrets

#### Scenario: Release text from trailers
- **WHEN** two commits since `v1.1.1` carry `Release-Note-de`/`Release-Note-en` and three do not, and `v1.1.2` is pushed
- **THEN** the release text lists the two notes in a German and an English section and nothing else

#### Scenario: No trailers in the range
- **WHEN** no commit since the previous release tag carries a release-note trailer
- **THEN** the run shows a warning and the text lists the commit subjects without task-mark and archive commits

### Requirement: Versions come from release tags
A tag `vX.Y` or `vX.Y.Z` SHALL set the version of everything CI builds for it, without the
version being edited in the project first. The tag SHALL be on main; a tag elsewhere or not
matching the pattern SHALL fail before building.

#### Scenario: New version by tag
- **WHEN** the project still says 1.1 and the user pushes the tag `v1.2` on main
- **THEN** the DMG and the App Store build are version 1.2

#### Scenario: Tag off main
- **WHEN** a tag `v1.3` is pushed on a commit that is not on main
- **THEN** the workflow fails with a message before building

### Requirement: Nightly builds
Once a night when main changed since the last nightly, and on demand, CI SHALL publish a
notarized DMG on one rolling pre-release "Nightly" that replaces the previous one. A nightly
has no release version: its version is `nightly-<commit date>`, its build number the commit
count, and its text names the commit and the changes since the last release. It SHALL never become GitHub's latest release.

#### Scenario: Changes on main
- **WHEN** commits were pushed to main during the day
- **THEN** the next night the "Nightly" pre-release holds a new notarized DMG of main's head

#### Scenario: Version of a nightly
- **WHEN** the nightly is built from a commit of 25 Oct 2026, number 214 on main
- **THEN** About Fernsy shows version "nightly-2026-10-25" with build 214

#### Scenario: Nothing changed
- **WHEN** main has not changed since the last nightly
- **THEN** no new nightly is built

#### Scenario: Website download
- **WHEN** a nightly is published
- **THEN** the website's download still delivers the last real release

### Requirement: App Store upload from a release tag
A release tag SHALL also build the App Store archive with Apple's cloud signing through the App
Store Connect API key and upload it to App Store Connect; submitting for review stays manual. A
release created by hand in GitHub SHALL keep its text and only get the DMGs attached.

#### Scenario: Releasing 1.2
- **WHEN** the tag `v1.2` is pushed on main
- **THEN** release "Fernsy 1.2" offers the notarized DMG and build 1.2 appears in App Store Connect for submission

#### Scenario: Release drafted on GitHub
- **WHEN** the user creates release `v1.2` with notes in the GitHub web interface
- **THEN** the workflow attaches the DMGs to it and leaves the notes as written

### Requirement: Signed update feeds
For every release and nightly, CI SHALL publish a Sparkle appcast signed with the EdDSA key
from the secret `SPARKLE_ED_PRIVATE_KEY`: the release's `appcast.xml` (reached through
`releases/latest`) and the nightly's `appcast.xml`, each pointing to its DMG with the build
number as version and the release notes in German and English (`xml:lang`), taken from the
commit trailers as for the release text.

#### Scenario: Release published
- **WHEN** the release workflow publishes 1.2.0
- **THEN** `releases/latest/download/appcast.xml` lists 1.2.0 with its DMG, signature and notes in German and English
