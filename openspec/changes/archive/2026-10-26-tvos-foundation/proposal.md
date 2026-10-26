# Proposal

## Why

Fernsy is getting an Apple TV app. Its screens are being designed in Claude Design right now,
and the next step is to build them. That step should only be about the screens. Today it
would have to start much lower down:

- Playback (FFmpeg, the session, the live tuner, timeshift, the slow-delivery rule) lives in
  the Mac app target. Only the provider and guide logic moved to `FernsyCore` so far
  (`fernsy-core-package`).
- FFmpeg is built for macOS only, as loose dylibs. tvOS needs it for the device and the
  simulator, and only accepts libraries as framework bundles.
- There is no tvOS target, no way to run and check it on this Mac, and no automated check.

A throwaway spike (2026-10-26, not in the repo) showed that `FernsyCore` itself compiles and
runs on tvOS: the demo channels and their guide came up in the tvOS simulator.

## What Changes

- FFmpeg is built as XCFrameworks of framework bundles for macOS, tvOS and the tvOS
  simulator, still LGPL-only and without encoders. The Mac app uses the same frameworks
  instead of the loose dylibs.
- Playback moves into a second local package, `FernsyPlayer` (FFmpeg bridge,
  byte sources, session, tuner and pool, timeshift buffer and writer, audio tap, renderers,
  the engine). The Mac app uses it unchanged in behavior. The video surface and picture in
  picture stay with each platform.
- A tvOS app target "Fernsy TV" (tvOS 27, SwiftUI) with a thin model over `FernsyCore` and
  `FernsyPlayer`, and deliberately plain placeholder screens: sign-in, channel list with the
  current show, full-screen player with play/pause, back 10 s, back to live. Each placeholder
  is the place a designed screen will replace, without touching the model.
- Development setup for the Apple TV app like the Mac app's: own bundle id and name, muted,
  streams only from the demo server, `scripts/tv-run.sh` that builds, starts the visible
  simulator and launches the app with debug switches, and a debug MCP server (own port) for
  play, seek, now playing, diagnostics, snapshot and log.
- A UI test that drives the app with the Siri Remote (to a channel, select, playing, back),
  run locally and in CI; CI also builds the Apple TV app.
- Universal purchase: the Apple TV app uses the Mac app's bundle id (`de.mobilistics.fernsy`,
  debug `de.mobilistics.fernsy.dev`), so one App Store record covers both.

## Capabilities

### New Capabilities

- `apple-tv`: the Apple TV app – what it does on Apple TV, how it relates to the Mac app's
  behavior, its storage limits, and its development builds.

### Modified Capabilities

- `distribution`: FFmpeg is shipped as framework bundles per platform; CI builds and tests the
  Apple TV app.

## Out of Scope

- The designed screens (next change, from the Claude Design screens), the tvOS look, Top
  Shelf, the guide grid, films, series, search, settings and Jellyfin on Apple TV.
- Recordings on Apple TV (tvOS has no lasting local storage); playing the Mac's recordings
  over the network.
- Coordinating the single stream between Mac and Apple TV.
- A real Apple TV device, TestFlight and the App Store record.
- Changing any behavior of the Mac app.

## Impact

- `scripts/build-ffmpeg.sh` (three platforms, XCFrameworks), `scripts/embed-ffmpeg.sh` and the
  "Embed FFmpeg" build phase (replaced by embedding the frameworks), BUILDINFO and credits.
- New `Packages/FernsyPlayer` (depends on `Packages/FernsyCore`): targets `CFFShim` (the C
  bridge), FFmpeg binary targets, `FernsyPlayer`; moved files from `Fernsy/Player`.
- `Fernsy.xcodeproj`: new target "Fernsy TV" and "Fernsy TV UITests", both app targets link
  `FernsyPlayer`.
- New `FernsyTV/` (app, model, placeholder screens, debug MCP), `scripts/tv-run.sh`.
- `.github/workflows/tests.yml` and `release.yml` (FFmpeg for tvOS, the Apple TV build, the UI
  test), DEVELOPMENT.md.
