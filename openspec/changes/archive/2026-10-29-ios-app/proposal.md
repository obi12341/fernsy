# Proposal

## Why

Fernsy runs on the Mac and on Apple TV. iPhone and iPad are where many people watch TV on the
couch, in bed or on the go, and the shared packages (FernsyCore, FernsyPlayer) already build
for two Apple platforms. An app for iPhone and iPad modelled on the Apple TV app brings the
same provider, guide and playback behaviour to touch devices, with little new logic.

## What Changes

- A new app target "Fernsy" for iPhone and iPad (iOS 27, one universal target), sold as a
  universal purchase with the Mac and Apple TV apps (same bundle id `de.mobilistics.fernsy`).
- It follows the Apple TV app: Start, Live TV (Liste and Programm, categories, all
  categories), films and series with their pages, Jellyfin (Übersicht, Filme, Serien,
  Bibliotheken), search, settings, the live player with timeshift, zapping and the channel
  list, the on-demand player with resume, tracks and the next-episode countdown, the player
  status, stall and failure cards, technical information, and iCloud sync, all operated by
  touch.
- On top of the Apple TV app it adds Picture in Picture and AirPlay.
- Layout adapts: a tab bar on iPhone, a sidebar-capable tab bar on iPad, and a full-screen
  landscape player on both.
- **No recordings on iPhone and iPad in v1.** iOS suspends apps in the background, and
  recordings are not synced between devices, so there is no Aufnahmen tab and no record
  actions.
- FFmpeg, FernsyCore and FernsyPlayer gain iOS and iOS-simulator support. The Apple TV app's
  model, image pipeline and player layers are shared with the new target instead of being
  copied.
- Development builds ("Fernsy Dev", demo server only, muted, debug MCP server on their own
  port) and a script that runs the app in the iOS simulator.

Out of scope:
- Recording, scheduling and a recordings list on iPhone and iPad, and recordings across
  devices.
- Downloads for offline viewing.
- Background audio without Picture in Picture, CarPlay, widgets, Live Activities, Siri and
  Shortcuts, Spotlight, and the MCP server for Claude (debug MCP only).
- Mac app changes beyond shared code, and Apple TV behaviour changes. Shared code may change
  only where both apps keep their behaviour.
- App Store listing texts, screenshots and the first submission. CI uploads come with the
  release workflow later; submitting stays manual.
- A redesign. Screens follow the Apple TV app's design language adapted for touch.

## Capabilities

### New Capabilities

- `ios-app`: Fernsy on iPhone and iPad. What the app does, how it shares the Mac and Apple TV
  apps' provider, guide and playback behaviour, what it adds (PiP, AirPlay) and leaves out
  (recordings), and how its development builds stay apart from real accounts.

### Modified Capabilities

- `distribution`: the universal purchase covers iOS as well. Release builds include the iOS
  app once its upload is wired into the release workflow (a later task in this change, or a
  follow-up).

## Impact

- New target and folder `FernsyiOS/` in `Fernsy.xcodeproj`. It shares `FernsyTV/Model`,
  `FernsyTV/Support` and parts of `FernsyTV/Player`.
- `Packages/FernsyCore/Package.swift` and `Packages/FernsyPlayer/Package.swift`: the `.iOS`
  platform.
- `scripts/build-ffmpeg.sh`: `ios` and `iossim` slices (CI's FFmpeg cache key follows the
  script).
- New `scripts/ios-run.sh`. `DEVELOPMENT.md` gets an iPhone/iPad section.
- String catalogs: the new target's German translations.
- The Apple TV app keeps working unchanged (shared files only gain `#if os(...)` where needed).
