# Tasks

## 1. Screenshots

- [ ] 1.1 `StoreShotsUITests` in `FernsyiOSUITests`: demo account (`IPTV_SERVER`/`IPTV_USER`/`IPTV_PASS` of the demo server), language from `STORE_LANGUAGE`, scenes live TV, guide, film page, player, search, recordings; skipped without `STORE_LANGUAGE`
- [ ] 1.2 `StoreShotsUITests` in `FernsyTVUITests`: Start, live TV with guide, film page, player, search, recordings, same switches
- [ ] 1.3 `scripts/store-media.sh shots`: simulators iPhone 18 Pro, iPhone Duo, iPad Pro 13-inch (M5), Apple TV 4K (3rd generation); status bar override; export attachments, drop alpha, check sizes; fail if a file is missing in German or English; output `dist/store/<platform>/<language>/`
- [ ] 1.4 Run it for German and English against the demo server and check every image by eye (no debug overlays, no real content)

## 2. App previews

- [ ] 2.1 `testPreview` in both shot tests: fixed sequence with marks in the app log (demo server, `IPTV_MCP=1` for the marks)
- [ ] 2.2 `scripts/store-preview.swift`: trim to the marks, scale/crop to 886 × 1920, 1200 × 1600, 1920 × 1080, 30 fps, silent stereo track
- [ ] 2.3 `scripts/store-media.sh previews` records with `simctl io recordVideo` and runs the script; check length (15–30 s), size and playback for German and English

## 3. Header and search images

- [ ] 3.1 `scripts/store-art/`: HTML for header (3840 × 1646) and search (3840 × 2560) using the shots from 1.4, line of text per language, safe area in the middle
- [ ] 3.2 `render.sh` with headless Chrome into `dist/store/ios/<language>/header.png` and `search.png`, no alpha; check both crops by eye

## 4. Texts

- [ ] 4.1 `docs/app-store.md`: sections iPhone/iPad and Apple TV (promotional text, description, keywords, what's new) in German and English, plus the image lines; `python3 scripts/check-store-texts.py` passes

## 5. Upload and wrap-up

- [ ] 5.1 User adds the German localization to the iOS and tvOS versions if missing, uploads the media and pastes the texts in App Store Connect (iOS and tvOS 1.0, German and English) and checks the header and search preview there
- [ ] 5.2 DEVELOPMENT.md (how to produce the store media); `openspec validate --all --strict`; archive, merge into `main`, push
