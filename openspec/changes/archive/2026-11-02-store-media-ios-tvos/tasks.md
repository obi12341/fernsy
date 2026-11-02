# Tasks

## 1. Screenshots

- [x] 1.1 iOS scenes opened by debug switches on the demo server (`IPTV_TAB`, `IPTV_LIVEVIEW`, `IPTV_DETAIL`, `IPTV_AUTOPLAY`, `IPTV_PLAYERMODE`, `IPTV_KEEPCONTROLS`, `IPTV_SEARCH`): Start, live list, guide, film page, series page, player, search (no recordings on iOS)
- [x] 1.2 Apple TV scenes the same way; the TV app gets `IPTV_LIVEVIEW`, `IPTV_KEEPCONTROLS` and `IPTV_SEARCH` as iOS has them; recordings with real show titles through the debug MCP server (`IPTV_MCP=1`, `record`, `cancel_recording`), after `IPTV_FRESHRECORDINGS=1`
- [x] 1.3 `scripts/store-media.sh shots` (launch per scene with `-AppleLanguages`, `simctl io screenshot`, `scripts/store-flatten.swift` drops alpha): simulators iPhone 18 Pro, iPhone Duo (inner display; stops with a hint while the simulator is folded), iPad Pro 13-inch (M5), Apple TV 4K (3rd generation); status bar override; check sizes; fail if a file is missing in German or English; output `dist/store/<platform>/<language>/`; fresh install per language; own builds named "Fernsy" in `build/store-*`
- [x] 1.4 Run it for German and English against the demo server and check every image by eye (no debug overlays, no real content)

## 2. App previews

- [x] 2.1 `StorePreviewUITests` (iOS and tvOS, skipped unless `TEST_RUNNER_STORE_LANGUAGE` is set): fixed walk with the demo account between the activities "store preview start" and "store preview end"; Apple TV plays a channel in the middle of the demo film (`TEST_RUNNER_STORE_CHANNEL_ROW`)
- [x] 2.2 `scripts/store-preview.swift`: trim to the marks, scale/crop to 886 × 1920, 1200 × 1600, 1920 × 1080, 30 fps, silent stereo track
- [x] 2.3 `scripts/store-media.sh previews` records with `simctl io recordVideo` and runs the script; check length (15–30 s), size and playback for German and English

## 3. Header and search images

- [x] 3.1 `scripts/store-art/`: HTML for header (3840 × 1646) and search (3840 × 2560) using the shots from 1.4, line of text per language, safe area in the middle
- [x] 3.2 `render.sh` with headless Chrome into `dist/store/ios/<language>/header.png` and `search.png`, no alpha; check both crops by eye

## 4. Texts

- [x] 4.1 `docs/app-store.md`: sections iPhone/iPad and Apple TV (promotional text, description, keywords; what's new only from 1.1 on) in German and English, plus the image lines; `python3 scripts/check-store-texts.py` passes

## 5. Upload and wrap-up

- [x] 5.1 User adds the German localization to the iOS and tvOS versions if missing, uploads the media and pastes the texts in App Store Connect (iOS and tvOS 1.0, German and English) and checks the header and search preview there
- [x] 5.2 DEVELOPMENT.md (how to produce the store media); `openspec validate --all --strict`; archive, merge into `main`, push
