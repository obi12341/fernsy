# Tasks

## 1. FFmpeg for three platforms

- [x] 1.1 `scripts/build-ffmpeg.sh` builds avutil, swresample, swscale, avcodec, avformat and avfilter for macOS arm64, tvOS arm64 and the tvOS simulator arm64 as dynamic framework bundles and combines them into XCFrameworks in `Packages/FernsyPlayer/Frameworks/` (git-ignored), same configure flags, GPL/nonfree check per slice, BUILDINFO and credits unchanged in content (design A). Verify: `vtool -show-build` per slice shows macOS 27 / tvOS 27 / tvOS-simulator 27; `otool -D` shows `@rpath/<lib>.framework/<lib>`; the script stops when `--enable-gpl` is added on purpose once.
- [x] 1.2 The Mac app links and embeds the frameworks with "Embed Frameworks" (sign on copy) instead of `embed-ffmpeg.sh` and its run-script phase; remove both. Verify: Debug, Direct and Release builds with 0 warnings; `otool -L` of the built app shows the frameworks; demo-server run (`scripts/dev-run.sh IPTV_AUTOPLAY=live:101`) plays; the built app contains only the six frameworks (no loose dylib) and passes `codesign --verify --deep --strict`. `scripts/build-dmg.sh` (its smoke test launches the release identity, which must not run next to the user's installed app) is verified by the nightly in CI before archiving.

## 2. `FernsyPlayer`

- [x] 2.1 Package `Packages/FernsyPlayer`: binary targets for the XCFrameworks, a `CFFShim` C target with `FFShim.c/h` and a module map, and the `FernsyPlayer` library (design B). Move the player files listed in design B, make the API the app uses `public`, strings with `bundle: .module` into the package catalog, `VideoSurface` and `PictureInPicture` stay in the Mac app. Verify: Debug, Direct and Release builds with 0 warnings; `scripts/test.sh` passes; `FernsyPlayer` builds for `generic/platform=tvOS Simulator`.
- [x] 2.2 Regression of the Mac app on the demo server: live with timeshift back and to live, film, episode, recording (`IPTV_TESTRECORD=101:5:60:0:0`), slow-delivery runs (`IPTV_TESTNET=trickle:30`; `IPTV_TESTNET=trickle:20 IPTV_TRICKLEMORE=all IPTV_TRICKLEKBIT=200`; `IPTV_TESTNET=drop:20`) with the same log lines as before, and Jellyfin play on a throwaway local Docker test server. Verify: MCP `playback_diagnostics` on port 52324 for each, window screenshots of the player.

## 3. "Fernsy TV" target

- [x] 3.1 tvOS app target "Fernsy TV" (design C): sources in `FernsyTV/`, links `FernsyCore` and `FernsyPlayer`, embeds the FFmpeg frameworks; universal purchase: Release `de.mobilistics.fernsy` ("Fernsy"), Debug `de.mobilistics.fernsy.dev` ("Fernsy Dev"), icon with the DEV band. Verify: builds for the tvOS simulator with 0 warnings; the built app contains the six FFmpeg frameworks and no loose dylib.
- [x] 3.2 `TVModel` per design D: credentials (env in debug), sign-in via `XtreamClient`, categories and channels with a JSON cache in Caches, guide via `EPGStore`, playback via `TunerPool` and `PlayerEngine` (`play`, `stop`, `togglePause`, `skip(-10)`, `goLive`), muted unless `IPTV_SOUND=1`, timeshift capped at 30 minutes (design F). Verify: the debug MCP `now_playing` (task 4.1) shows the channel, `behind_live_seconds` after `seek by_seconds:-10`, and the demo-server guard refuses `IPTV_SERVER=https://example.invalid` with the error text.
- [x] 3.3 Placeholder screens (`SignInScreen`, `ChannelListScreen`, `PlayerScreen`) with the accessibility identifiers of design G and a tvOS video surface hosting the engine's display layer. Verify: `scripts/tv-run.sh` shows the demo channels with their current show, selecting one plays it full screen (simulator screenshot via `simctl io`), Back returns to the list with the channel focused.

## 4. Development setup

- [x] 4.1 `MCPHTTPServer` and the JSON-RPC part of `MCPServer` (as `MCPDispatcher`) move to `FernsyCore`; the Mac app's MCP behaves as before; `FernsyTV/Debug/TVTools.swift` with `play`, `stop_playback`, `seek`, `now_playing`, `playback_diagnostics`, `snapshot`, `get_log` on port 52325, DEBUG only (design E). Verify: Mac dev build MCP on 52324 answers `whats_on` and `play`; Apple TV MCP on 52325 answers all seven tools during a demo run; a Release build of the Apple TV app has no listener (`lsof -i :52325` empty while it runs in the simulator).
- [x] 4.2 `scripts/tv-run.sh` per design E (build at background priority, boot and show the simulator, install, launch with `SIMCTL_CHILD_` env, log file, demo defaults, `KEY=value` passthrough). Verify: `scripts/tv-run.sh --log build/devtest/tv.log IPTV_AUTOPLAY=live:101` ends with the app playing channel 101 in the visible simulator, without sound, and the log has "connected (HTTP 200)".
- [x] 4.3 `Fernsy TV UITests` per design G, run by `scripts/tv-uitest.sh`. Verify: `scripts/tv-uitest.sh` passes; with the player's state identifier renamed on purpose once, it fails.

## 5. CI and docs

- [x] 5.1 `tests.yml`: FFmpeg from the cache or built (three slices), the Apple TV app built for the simulator, the UI test (design H); `release.yml` jobs use the new frameworks. Verify: a push of the branch runs green; a manual `appstore-test` run of `release.yml` on the branch exports the App Store build with the embedded frameworks.
- [x] 5.2 DEVELOPMENT.md: section "Apple TV" (targets and identities, `tv-run.sh`, debug switches, MCP port 52325, screenshots via `simctl io`, where the screens live and which slots the designs replace, what the simulator cannot show). Update the FFmpeg section for the XCFrameworks. Verify: the section exists and names every switch and the screen slots.
- [x] 5.3 `openspec validate --all --strict` exits 0; Mac Debug, Direct, Release and the Apple TV Debug build have 0 warnings; `scripts/test.sh --tvos-sim` passes.

## Workflow follow-up

- Internal change for Mac users, no Release-Note trailers (the Apple TV app is not shipped).
- Before archiving: the nightly DMG with the new FFmpeg frameworks is notarized and launches (CI), and the `appstore-test` export succeeds.
- Adding tvOS to the App Store record (universal purchase) happens with the first TestFlight build, in a later change.
- Next change: the designed screens from Claude Design, starting from DEVELOPMENT.md › Apple TV › screen slots.
