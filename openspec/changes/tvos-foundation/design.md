# Design

## Context

- `Packages/FernsyCore` (macOS 27, tvOS 27) holds provider, guide, Jellyfin models, channel
  names, recording plan and gaps, the slow-delivery rule, track choice, media info and the
  log, with 44 tests that CI also runs on a tvOS simulator.
- Playback is in `Fernsy/Player` (about 5,900 lines). Only `VideoSurface.swift` and
  `PictureInPicture.swift` use AppKit. `PlaybackSession` uses `UserDefaults` (audio rescue
  PIDs) and defines `PlayerError`, `PlayerEngine` stores the volume; both work on tvOS.
  `FFShim.c/h` and the bridging header expose FFmpeg to Swift.
- FFmpeg 9.0.2 is built by `scripts/build-ffmpeg.sh` for macOS arm64 only, as loose dylibs
  in `Vendor/ffmpeg` (git-ignored, 18 MB, cached in CI by the script's hash), embedded and
  signed by `scripts/embed-ffmpeg.sh` in an "Embed FFmpeg" run-script phase.
- MCP: `MCPHTTPServer.swift` (Network framework) has no app dependencies, `MCPServer.swift`
  (JSON-RPC) two small ones; `MCPTools.swift` is tied to the Mac app's `AppModel`.
- A throwaway spike compiled `FernsyCore`'s sources straight into a tvOS app and showed the
  demo channels with their guide in the tvOS 27 simulator (Apple TV 4K 3rd generation).
- On this Mac: Xcode 27.1, tvOS 27 SDK and simulator runtime installed; Xcode 27.1 has no
  separate `Simulator.app` – the user saw the booted simulator in Xcode. No Apple TV is paired.
- The user is designing the Apple TV screens in Claude Design; they are built in the next
  change.

## Goals / Non-Goals

**Goals:**
- After this change, building a designed screen means writing SwiftUI views against a
  ready model, and checking them in the simulator, without touching FFmpeg, playback or the
  project setup.
- The Apple TV app plays the demo channels with the Mac app's playback behavior.
- The same development comfort as the Mac app: one script to run it, a debug MCP server,
  screenshots, a UI test, CI.
- No behavior change in the Mac app.

**Non-Goals:**
- Designed screens, tvOS look and feel, Top Shelf, guide grid, films, series, search,
  settings, Jellyfin, recordings on Apple TV (see proposal).

## Decisions

### A. FFmpeg as XCFrameworks of framework bundles, for all platforms

`scripts/build-ffmpeg.sh` builds each library the Mac app links today (avutil, swresample, swscale, avcodec,
avformat, avfilter) for three slices: macOS arm64, tvOS arm64 (`appletvos`) and the
tvOS simulator arm64 (`appletvsimulator`), each as a dynamic `.framework` bundle (install name
`@rpath/<lib>.framework/<lib>`, Info.plist with the FFmpeg version), and combines them with
`xcodebuild -create-xcframework` into `Packages/FernsyPlayer/Frameworks/<lib>.xcframework`
(git-ignored), with the headers in `Packages/FernsyPlayer/Sources/CFFShim/include/lib*` and
BUILDINFO and the LGPL text next to the frameworks. `Vendor/ffmpeg` goes away. The
configure flags stay the same (LGPL only, no encoders, the existing component list); the
GPL/nonfree check runs per slice. BUILDINFO and the credits keep naming the source archive.

The Mac app switches to the same frameworks: one way to link FFmpeg everywhere, embedded and
signed by Xcode's "Embed Frameworks" (sign on copy), which replaces `embed-ffmpeg.sh` and the
run-script phase.

Rejected: XCFrameworks only for tvOS, loose dylibs for macOS as today. The shared player
library (decision B) links FFmpeg once for all platforms; two linking schemes would mean two
module maps and two embedding paths. Rejected: static libraries. LGPL needs the user to be
able to replace the library, which dynamic frameworks allow and a static link does not.

Risk handled by tasks: the DMG's notarization and the App Store export validate embedded
frameworks differently from loose dylibs; both are verified (nightly DMG, `appstore-test` CI
run) before the change is archived.

### B. `FernsyPlayer`: a second local package

`Packages/FernsyPlayer` (macOS 27, tvOS 27) depends on `../FernsyCore` by path and contains:
- binary targets for the FFmpeg XCFrameworks (SwiftPM requires binary targets inside the
  package directory);
- `CFFShim`, a C target with `FFShim.c/h` and a module map (`module CFFShim { header
  "FFShim.h" }`), replacing the bridging header; the FFmpeg headers sit in its public include
  folder, so every client finds them. The app imports `CFFShim` too (the Jellyfin codec check,
  the MCP mux delay);
- `FernsyPlayer`, depending on `FernsyCore` and `CFFShim`, with `ByteSource`,
  `HTTPByteSource`, `BufferByteSource`, `FileByteSource` (all in `ByteSource.swift` and `HTTPByteSource.swift`), `PacketQueue`,
  `TSAudioTap`, `TimeshiftBuffer`, `TimeshiftWriter`, `LiveTuner`, `TunerPool`,
  `PlaybackSession` (with `PlayerError`), `RendererSinks`, `DVDecoder`, `FrameGrabber`,
  `MediaNames+FFmpeg` and `PlayerEngine`.

`VideoSurface` (NSView) and `PictureInPicture` stay in the Mac app; the Apple TV app gets its
own surface (a `UIView` hosting the engine's `AVSampleBufferDisplayLayer`).

Rejected: a second library inside `Packages/FernsyCore` (the first plan). A package with
binary targets cannot even be loaded until they exist, so `FernsyCore`'s tests would need an
FFmpeg build first – in CI too. A package of its own keeps `FernsyCore` free of FFmpeg.

Access control and `Sendable` follow the pattern of `fernsy-core-package` (public API,
generated memberwise inits where the app constructs values, strings with
`bundle: .module`).

Rejected: compiling the player files into both app targets by file membership. It works
without a package change, but the code would stay untestable outside an app, and every new
platform would repeat the membership. Rejected: moving the Mac app's `AppModel` as well. It
mixes catalog caching, recordings, Siri, the menu bar and windows; the Apple TV app needs a
small part of it (decision D).

### C. Target "Fernsy TV" in the same project

A tvOS application target in `Fernsy.xcodeproj`, sources in `FernsyTV/`
(file-system-synchronized group like `Fernsy/`), SwiftUI, tvOS 27, Apple TV 4K, linking
`FernsyCore` and `FernsyPlayer` and embedding the FFmpeg frameworks. Swift language mode 5
like the rest.

Identity: universal purchase with the Mac app (the user's decision, 2026-10-26): Release uses
the Mac app's bundle id `de.mobilistics.fernsy`, Debug the Mac dev build's
`de.mobilistics.fernsy.dev`, display names "Fernsy" and "Fernsy Dev", the debug icon with the
"DEV" band (top shelf and app icon layers from the Mac icon). One App Store record then sells
both; the tvOS platform is added to it when the first TestFlight build is uploaded (outside
this change).

Rejected: a separate Apple TV app (`de.mobilistics.fernsy.tv`). A second record with its own
price and reviews, and buyers of the Mac app would pay again.

Rejected: a separate Xcode project or a Swift Playgrounds-style package app. One project
keeps one scheme list, one CI build and shared settings.

### D. A thin model and placeholder screens, shaped for the designs

`FernsyTV/Model/TVModel.swift` (`@MainActor ObservableObject`) owns what screens read:
- account: credentials (debug: from the environment like the Mac app; keychain on tvOS for
  later sign-in), sign-in state and errors from `XtreamClient`;
- catalog: live categories and channels, loaded with `XtreamClient` and cached as JSON in
  Caches (decision F); the guide through `FernsyCore`'s `EPGStore`;
- playback: a `TunerPool` and a `PlayerEngine` from `FernsyPlayer`, with `play(channel)`,
  `stop()`, `togglePause()`, `skip(-10)`, `goLive()` and the published engine state.

Screens are plain SwiftUI in `FernsyTV/Screens/`: `SignInScreen` (debug: shows which account
is used), `ChannelListScreen` (categories as sections, channel with the current show),
`PlayerScreen` (full-screen video, a minimal overlay with title, time and live state, remote
commands mapped to the model). Each reads only `TVModel`, so a designed screen replaces a
file. The file layout and the list of screen slots go into DEVELOPMENT.md, so the design
change starts there.

Rejected: building placeholder screens that imitate a tvOS look. They would be thrown away
with the designs and invite reviewing a look nobody chose.

### E. Debug setup like the Mac app

- Muted at start unless `IPTV_SOUND=1`, the demo-server guard of `PlayerError.debugAllows` (it
  moves with `PlaybackSession`), and credentials from `IPTV_SERVER/IPTV_USER/IPTV_PASS` with
  `FERNSY_NO_KEYCHAIN=1`.
- Debug MCP server: `MCPHTTPServer` and `MCPServer` move to `FernsyCore` (the two app
  references become parameters); the Apple TV app registers its own small tool set in
  `FernsyTV/Debug/TVTools.swift` – `play`, `stop_playback`, `seek`, `now_playing`,
  `playback_diagnostics`, `snapshot`, `get_log` – on port 52325 with `IPTV_MCPTOKEN`, DEBUG only.
  The simulator shares the Mac's network, so `127.0.0.1:52325` reaches it. Release builds of
  the Apple TV app have no MCP server.
- `scripts/tv-run.sh [--no-build] [--log <file>] [KEY=value …]`: builds the "Fernsy TV" scheme
  for the simulator (`taskpolicy -b`), boots the Apple TV 4K (3rd generation) simulator, shows
  it (`open -a Simulator` when that app exists; Xcode 27.1 shows booted simulators itself),
  installs and launches with `SIMCTL_CHILD_`-prefixed variables and the console to a log file.
  The demo env is the default, as in `dev-run.sh`.
- Screenshots with `xcrun simctl io <id> screenshot`, never of the user's screen; the app is
  driven by env switches, MCP and the UI test, never by keyboard or mouse input.

### F. Storage on tvOS

The timeshift buffer goes to Caches, as on the Mac, with the buffer length capped at 30 minutes
by default on Apple TV (it is disk the system may need). The catalog cache is JSON in Caches.
Everything tolerates a missing folder. Nothing is written outside Caches except settings in
`UserDefaults` (small).

Rejected: iCloud key-value storage for the catalog. It is limited to 1 MB and meant for
settings; it can carry favorites later.

### G. UI test with the Siri Remote

`Fernsy TV UITests` launches the app with the demo env, presses Down to reach a channel,
Select, waits for the player's accessibility value `playing`, presses Back and checks the list
is shown with the same channel focused. Placeholder screens expose accessibility identifiers
(`channel.<id>`, `player.state`) that the designed screens keep.

### H. CI

`tests.yml` gets a job that restores or builds FFmpeg (cache key: the script's hash, now with
three slices), builds the Apple TV app for the simulator and runs the UI test. `release.yml`
already depends on `tests.yml`, so a broken Apple TV build stops nightlies too. The DMG and
App Store jobs use the frameworks from the same cache.

## Risks / Trade-offs

- [FFmpeg's configure for tvOS needs different flags (no `--target-os=darwin` assumptions,
  sysroot, `-mtvos-version-min`, no inline asm issues)] → the first task is the build alone,
  checked with `lipo`/`vtool` per slice before anything links it.
- [Notarization or App Store validation treats the new frameworks differently] → verified
  with the nightly DMG and an `appstore-test` run before archiving.
- [Moving 5,900 lines of playback changes the Mac app by accident] → no logic edits besides
  access control; the demo runs of `slow-live-stream-reconnect` and the smoke run (live,
  timeshift, film, episode, Jellyfin on a local test server) are repeated.
- [The tvOS simulator decodes with the Mac's hardware] → playback performance on Apple TV is
  unknown until a device is paired; out of scope here, noted in DEVELOPMENT.md.
- [The design screens need data the model does not offer yet] → `TVModel` covers the live
  path; the design change extends it per screen, which is cheap because the data already
  comes from `FernsyCore`.
