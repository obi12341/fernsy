## MODIFIED Requirements

### Requirement: LGPL-only FFmpeg
Bundled FFmpeg SHALL be built from source without GPL or nonfree components and without
encoders, as dynamic framework bundles inside the app, for every platform Fernsy ships on
(macOS, tvOS, iOS, and the tvOS and iOS simulators for development); the credits SHALL name
FFmpeg, the LGPL and the exact source archive.

#### Scenario: Building FFmpeg
- **WHEN** `scripts/build-ffmpeg.sh` runs
- **THEN** it refuses to finish if the configuration enables GPL or nonfree code

#### Scenario: Libraries on Apple TV
- **WHEN** the Apple TV app is built
- **THEN** each FFmpeg library is an embedded framework, and the app contains no FFmpeg code linked statically

#### Scenario: Libraries on iPhone and iPad
- **WHEN** the iPhone and iPad app is built
- **THEN** each FFmpeg library is an embedded framework, and the app contains no FFmpeg code linked statically

## ADDED Requirements

### Requirement: iPhone and iPad app in CI
CI SHALL build the iPhone and iPad app for the iOS simulator on pushes to `main` that change
more than specs and docs, and on pull requests; a nightly or release SHALL NOT be built from a
commit where it fails to build.

#### Scenario: The iPhone app stops building
- **WHEN** a commit breaks the iOS target
- **THEN** the push's CI run fails, and no nightly is published from it
