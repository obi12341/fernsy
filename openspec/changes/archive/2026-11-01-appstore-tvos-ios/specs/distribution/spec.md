## MODIFIED Requirements

### Requirement: App Store upload from a release tag
A release tag SHALL also archive the Mac, Apple TV (with Top Shelf) and iPhone/iPad apps with
Apple's cloud signing through the API key, with the tag's version and one build number, and
upload all three to App Store Connect; submitting stays manual. The GitHub release SHALL appear
only when the DMG and all three uploads succeeded; a hand-made release keeps its text. A manual
App Store test SHALL export all three without uploading.

#### Scenario: Releasing 1.2
- **WHEN** the tag `v1.2` is pushed on main
- **THEN** release "Fernsy 1.2" offers the notarized DMG, and build 1.2 appears in App Store Connect for macOS, tvOS and iOS for submission

#### Scenario: One platform's upload fails
- **WHEN** the Apple TV archive fails while the Mac and iOS uploads succeed
- **THEN** the run fails, no GitHub release is published, and the failed job can be rerun alone

#### Scenario: App Store test run
- **WHEN** the workflow is run manually with the App Store test channel
- **THEN** it exports a Mac, an Apple TV and an iOS package and uploads nothing

#### Scenario: Release drafted on GitHub
- **WHEN** the user creates release `v1.2` with notes in the GitHub web interface
- **THEN** the workflow attaches the DMGs to it and leaves the notes as written
