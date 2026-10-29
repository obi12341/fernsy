# Design

## Context

- The Apple TV app (`FernsyTV/`, target "Fernsy TV", about 7,300 lines) sits on FernsyCore and
  FernsyPlayer. Its logic lives in `TVModel` (`FernsyTV/Model`, about 1,400 lines, Foundation
  and UIKit only: `isIdleTimerDisabled`). `FernsyTV/Support` holds the image pipeline, the
  living backdrop and frame stats. `FernsyTV/Player` holds the video surface
  (`AVSampleBufferDisplayLayer` in a `UIView`), the technical-info panel and the status
  layer. The screens (`FernsyTV/Screens`, `Design`) are focus-driven tvOS UI.
- The project uses file-system synchronized groups (Xcode 16+, `objectVersion = 77`). A
  folder's files belong to a target through the group plus exception sets.
- The Mac app's Picture in Picture (`Fernsy/Player/PictureInPicture.swift`) already uses
  `AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer:playbackDelegate:)` on
  the engine's display layer. The macOS-only scaling workaround (`PictureInPictureStage`) is
  not needed on iOS.
- `de.mobilistics.fernsy` is a universal purchase (Mac, Apple TV). Debug builds use
  `de.mobilistics.fernsy.dev`, "Fernsy Dev". The debug MCP ports: Mac app 52323/52324, Apple
  TV 52325.
- FFmpeg comes from `scripts/build-ffmpeg.sh` as one XCFramework per library with a slice per
  platform.
- Decisions taken with the user (2026-10-29): iPhone and iPad in v1; no recordings; PiP and
  AirPlay in; built after the Apple TV app's model.

## Goals / Non-Goals

**Goals:** a touch app with the Apple TV app's features minus recordings, sharing its model
code; PiP and AirPlay; development builds and a simulator script like the Apple TV app's.

**Non-Goals:** see proposal. Also no shared-UI layer between tvOS and iOS: the screens differ
too much (focus vs. touch).

## Decisions

### 1. One iOS target for iPhone and iPad
A target "Fernsy iOS" (product name `Fernsy`, folder `FernsyiOS/`) with
`TARGETED_DEVICE_FAMILY = 1,2`, iOS 27, bundle id `de.mobilistics.fernsy` (Debug:
`.dev`, "Fernsy Dev"), the same team and entitlements style as the Apple TV target (keychain
group, iCloud key-value store for sync).
- Rejected: separate iPhone and iPad targets. They would double the setup for layouts that
  SwiftUI adapts by size class anyway.
- Rejected: Mac Catalyst or "Designed for iPad" on the Mac. The Mac has its own app.

### 2. Share the Apple TV app's model by target membership, not by copying or moving
The iOS target includes the `FernsyTV` synchronized group with an exception set listing the
tvOS-only files: `FernsyTVApp.swift`, every file in `Screens/`, `Design/TVTextEntry.swift`, the
asset catalog and `InfoPlist.xcstrings`. Xcode does not accept folders in that list (it dropped
them when it rewrote the project), so a new screen file must be added to it. `Model/`,
`Support/`, `Player/`, `Debug/` (the debug MCP server, port 52326 on iOS), `Design/TVTheme.swift`
(colours and button styles, so both apps look alike) and `Localizable.xcstrings` are shared.
Platform differences inside shared files use `#if os(tvOS)`. Two were needed: the focus
section and exit command of `PlayerStatusLayer`'s failure card, and the debug port. The
tvOS screens' `IPTVSignInScreen` (named by `TVModel+Sync`) and `ActionButtonStyle` (used by the
status layer) have iOS counterparts in `FernsyiOS/`.
- Rejected: copying the model into `FernsyiOS/`. Two copies drift; every provider or Jellyfin
  fix would need to be made twice.
- Rejected: moving the shared files into a new package or folder now. The other agent works in
  `FernsyTV/` on its branches, so a move would conflict with every one of them. The FernsyCore
  split is planned as its own step for 2.x. A later change can move and rename (`TVModel` →
  a neutral name) once both apps use it.

### 3. Navigation with SwiftUI's tab API
`TabView` with `Tab` values and `.tabViewStyle(.sidebarAdaptable)`: a bottom tab bar on
iPhone, a top tab bar that turns into a sidebar on iPad. Each tab has a `NavigationStack`.
Suche is a `Tab(role: .search)`. Tabs follow the same visibility rules as the Apple TV app
(`TVModel`'s signed-in state and the films/series switches).
- Rejected: copying tvOS's custom top tab bar. Touch users expect the system bars, and
  sidebarAdaptable gives the iPad sidebar for free.

### 4. Player as a full-screen cover, landscape on iPhone
`fullScreenCover` hosting the shared `TVVideoSurface` (engine display layer) with touch
controls on top. On iPhone it requests landscape through
`UIWindowScene.requestGeometryUpdate` while open. After it closes, the app turns to the way the
device is held (portrait when flat or unknown). The request goes in the cover's `onDismiss`: from
the player's `onDisappear` it comes while the player's landscape-only controller is still on
screen, and it is refused. The app declares all orientations. Controls: tap toggles them, with auto-hide after 4 s. The timeline
is a system `Slider` (as on the Mac since `system-slider-timeline`). Swipe down closes;
sideways swipes on the picture zap (live only, controls hidden). Status, stall and failure cards reuse
`PlayerStatusLayer` and the technical panel reuses `StreamInfoPanel`.

### 5. Picture in Picture
Port the Mac's `PictureInPicture` controller (without the macOS stage) into `FernsyiOS/`.
`canStartPictureInPictureAutomaticallyFromInline = true` gives the automatic start when the app
leaves. The audio session category is `.playback` (`.moviePlayback` mode), and the target gets
background mode `audio`, which PiP requires. While PiP runs, the full-screen cover is
dismissed. "Restore" reopens it. Closing PiP stops playback like closing the player.
`TVModel.appWillLeave()` (stops streams when the app leaves on tvOS) must not stop playback while
PiP is active or starting.

### 6. AirPlay: route picker for sound, external-display scene for the picture
The player shows `AVRoutePickerView`. The engine renders audio through
`AVSampleBufferAudioRenderer`, which follows the audio session's route, so AirPlay speakers
work without more code. FernsyPlayer renders video into a layer itself (no `AVPlayer`), so
there is no AirPlay video stream. Instead, when the user mirrors to an AirPlay screen, iOS
offers an external display. The app then presents a second, non-interactive window scene
(`UIWindowSceneSessionRole.windowExternalDisplayNonInteractive`) that hosts the display layer
full screen, while the phone keeps the controls and shows "Wird auf <Gerät> abgespielt".
- **v1 ships plain screen mirroring** (assumption taken on 2026-10-29 at night, to be confirmed
  by the user): the external-display scene cannot be tried in the simulator (it has no AirPlay,
  and its external-display menu needs UI input), and a blind implementation could turn a working
  mirror into a black TV. iOS mirrors the player full screen by itself, sound included, so the
  spec's AirPlay-screen scenario now asks for that. The dedicated scene (phone keeps the
  controls, the TV shows only the picture) stays a follow-up with task 7.1 as its spike on a
  real device.
- Rejected: building an `AVPlayer` path (HLS) for AirPlay. It would need a second playback
  stack and a server-side HLS stream the provider does not offer.

### 6a. Choices made while building (2026-10-29, at night)
Taken without the user, to be confirmed:
- **Settings on iPhone:** a gear on Start instead of a tab. An iPhone tab bar shows five tabs,
  and a sixth collapses into "More". On iPad Settings stays a tab.
- **Channel list in the player:** a panel at the trailing edge with the picture beside it. A
  sheet covers the whole screen in landscape.
- **Live TV's source:** a toolbar menu (Favorites, Recently Watched, All Channels, pinned,
  All Categories) instead of the Apple TV's category column. On iPad in landscape, the pane
  beside the list follows the row whose info button was tapped (a tap on the row plays).
- **Guide:** twelve hours ahead (and back to the shown channels' archive), scrolled by touch,
  opening half an hour before now. A later show opens a details sheet with "Watch Channel"
  instead of the Apple TV's record question.
- **Player controls:** back 10 s, play/pause and forward 10 s in the middle, a system slider
  for the timeline (as on the Mac), tracks as a menu, then Picture in Picture, AirPlay and the
  channel list at the top right, each with a 44-point target (the symbols alone were too small to
  hit, found by the UI test). They hide after 4 s. Swipe down always closes. Left and right
  swipes zap while the controls are hidden. The first version zapped with up and down, so "down"
  meant close or previous channel depending on whether the controls had just hidden.
- **Debug switches for screenshots** (the simulator takes no touch input from scripts):
  `IPTV_TAB`, `IPTV_LIVEVIEW`, `IPTV_ALLCATEGORIES`, `IPTV_DETAIL`, `IPTV_SEARCH`,
  `IPTV_PLAYERMODE=channels`, `IPTV_KEEPCONTROLS` (DEVELOPMENT.md).
- **Picture in Picture in the simulator:** unsupported. The controller is only created where
  `isPictureInPictureSupported()`, because elsewhere AVKit hands back a null object that crashes
  on first use.
- **UI tests found two bugs that screenshots hid:** the top bar's symbols were too small to hit
  (now 44-point targets), and "down" closed or zapped depending on the controls' timer (now down
  always closes and sideways zaps). A target "Fernsy iOS UITests" with `scripts/ios-uitest.sh`
  keeps them covered on iPhone and iPad.
- **Missing German strings of the Apple TV screens** (DIRECTOR, CAST, AUDIO) were added to the
  shared catalog too.

### 7. No recordings on iOS
The shared `TVModel+Recordings` stays compiled (it is part of the model). On iOS no screen
offers to record, schedule or list recordings, and Start leaves out "Deine Aufnahmen". The
recorder is still activated per account, but it only acts on recordings scheduled on this
device, and there are none (recordings are not synced). So a `supportsRecording` flag was not
needed. If shared code ever starts a recording by itself, it needs an `#if os(tvOS)` guard.

### 8. FFmpeg slices for iOS
`build-ffmpeg.sh` gains `ios` and `iossim` (same configure flags as tvOS with the iPhone
SDKs and `-target arm64-apple-ios27[-simulator]`), framework bundles shallow like on tvOS.
The packages add `.iOS("27.0")`. CI rebuilds FFmpeg automatically because its cache key hashes
the script.

### 9. Development builds and tooling
Debug builds: bundle id `.dev`, name "Fernsy Dev", start muted, refuse non-demo servers
(`IPTV_ALLOWREAL` as on the Apple TV), own Jellyfin device id. The debug MCP server reuses
`TVDebugServer` (`FernsyTV/Debug/TVTools.swift`, shared into the iOS target) with port 52326
on iOS. `scripts/ios-run.sh` mirrors `tv-run.sh`: it builds, boots an iPhone simulator
(visible window), installs and launches with `SIMCTL_CHILD_*` debug variables.
Screenshots come from `xcrun simctl io`.

### 10. Strings and assets
The iOS target shares `FernsyTV/Localizable.xcstrings` (shared model strings already have
their German translations there), and iOS-only strings are extracted into the same catalog. It
has its own `Assets.xcassets` with the app icon (from the Mac icon artwork) and accent colour,
and its own `InfoPlist.xcstrings`.
- Rejected: a second `Localizable.xcstrings` in `FernsyiOS/`. A target can only have one
  catalog per table name, and shared strings would need translating twice.

## Risks / Trade-offs

- [`TVModel` assumes tvOS lifecycle (`appWillLeave` stops playback)] → iOS passes PiP state.
  Covered by decision 5 and tested with PiP on leave.
- [Shared files gain `#if os` branches] → kept minimal. Each one is a candidate for the later
  move and rename.
- [AirPlay video may not work with the display layer in an external scene] → spike first,
  documented fallback.
- [Simulator lacks VideoToolbox HW decode paths, PiP and AirPlay] → the simulator verifies
  UI and flow. PiP and AirPlay need a real device (the user's iPhone or iPad), and those
  checks are listed as user checks at the end.
- [Catalog performance on phones (30,000 films)] → the Apple TV app's lazy grids and row
  caching come along with the model. Same measures apply.
- [CI time: one more target and FFmpeg slices] → FFmpeg is cached. The iOS build only builds,
  without UI tests in v1.

## Migration Plan

No data migration: a new target. Rollback means dropping the target; the packages and the
FFmpeg script keep working for macOS and tvOS with the extra slices.

## Open Questions

- Whether the App Store record needs anything beyond adding the iOS platform for the universal
  purchase (screenshots, privacy details for iOS). This is answered at the first TestFlight
  upload and does not affect the code.
