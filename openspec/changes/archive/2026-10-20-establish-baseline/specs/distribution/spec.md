## Purpose

How Fernsy is built and shipped: the Mac App Store build, the DMG for direct installation,
and the licensing obligations of the bundled third-party code.

## ADDED Requirements

### Requirement: Mac App Store build
The App Store build SHALL be sandboxed (network client only, plus what features add), arm64
only, signed with automatic signing for team B8YT7FNB66, declare no non-exempt encryption,
include a privacy manifest, and get a new build number for every upload.

#### Scenario: Uploading a build
- **WHEN** `UPLOAD=1 scripts/build-appstore.sh` runs
- **THEN** the build number is incremented, the archive is exported and uploaded to App Store Connect

### Requirement: DMG for direct installation
`scripts/build-dmg.sh` SHALL produce `dist/Fernsy-<version>.dmg`, ad-hoc signed by default or
with a given identity (optionally notarized), after a launch smoke test that loads the
FFmpeg libraries from the bundle only.

#### Scenario: Local test build
- **WHEN** the script runs with `SIGN_IDENTITY="Apple Development: …"`
- **THEN** the DMG contains an app whose keychain access survives rebuilds

### Requirement: LGPL-only FFmpeg
Bundled FFmpeg SHALL be built from source without GPL or nonfree components and without
encoders, as shared libraries inside the app; the credits SHALL name FFmpeg, the LGPL and
the exact source archive.

#### Scenario: Building FFmpeg
- **WHEN** `scripts/build-ffmpeg.sh` runs
- **THEN** it refuses to finish if the configuration enables GPL or nonfree code

### Requirement: Store texts within limits
Store texts (name, subtitle, promotional text, description, keywords, what's new) SHALL be
kept in `docs/app-store.md` in German and English and stay within App Store Connect limits.

#### Scenario: Checking texts
- **WHEN** `python3 scripts/check-store-texts.py` runs
- **THEN** every field is reported within its character limit
