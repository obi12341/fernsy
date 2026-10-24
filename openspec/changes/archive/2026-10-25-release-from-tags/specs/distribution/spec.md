## MODIFIED Requirements

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

## ADDED Requirements

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
