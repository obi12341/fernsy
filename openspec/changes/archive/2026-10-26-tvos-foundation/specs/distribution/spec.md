## MODIFIED Requirements

### Requirement: LGPL-only FFmpeg
Bundled FFmpeg SHALL be built from source without GPL or nonfree components and without
encoders, as dynamic framework bundles inside the app, for every platform Fernsy ships on
(macOS, tvOS and the tvOS simulator for development); the credits SHALL name FFmpeg, the LGPL
and the exact source archive.

#### Scenario: Building FFmpeg
- **WHEN** `scripts/build-ffmpeg.sh` runs
- **THEN** it refuses to finish if the configuration enables GPL or nonfree code

#### Scenario: Libraries on Apple TV
- **WHEN** the Apple TV app is built
- **THEN** each FFmpeg library is an embedded framework, and the app contains no FFmpeg code linked statically

## ADDED Requirements

### Requirement: Apple TV app in CI
CI SHALL build the Apple TV app for the tvOS simulator and run its UI test with the demo
account on every push to `main` and to change branches, and a nightly or release SHALL NOT be
built when that fails.

#### Scenario: The Apple TV app stops building
- **WHEN** a commit breaks the Apple TV target
- **THEN** the push's CI run fails, and no nightly is published from it
