# Tasks

## 1. Spike and target

- [x] 1.1 Spike on "Apple TV WZ" (Release build): a minimal Top Shelf extension returning one row with an image from the App Group container (`file://`). Record in design.md whether tvOS shows it; if not, stop and decide the image path with the user (design 2). Done 2026-11-01 on "Apple TV WZ": the tiles show the images from `Library/Caches` of the App Group container
- [x] 1.2 Add the `FernsyTopShelf` target (folder, Info.plist with `NSExtensionPointIdentifier` `com.apple.tv-top-shelf`, entitlements with the App Group, embedded in the Apple TV app); dev and release bundle ids and App Groups (design 5, 7); Debug and Release builds of the TV scheme succeed
- [x] 1.3 App Group entitlement in `Config/FernsyTV.entitlements` and in the device-build copies (`build/tv-device/release.entitlements` recipe in DEVELOPMENT.md)

## 2. Deep links

- [x] 2.1 Declare the URL scheme in `Config/Info-TV.plist` (design 3): `fernsy` in release builds, `fernsy-dev` in debug builds (`FERNSY_URL_SCHEME`); the uncommitted change that had been lying in the file since 2026-10-29 was discarded with the user's OK
- [x] 2.2 `TVModel.play(itemId:)`/`open(itemId:)` for `movie:`, `episode:`, `jellyfin:`, `live:`, `recording:`; `TVTools.play_item` uses it; `onOpenURL` handles `fernsy://play` and `fernsy://open` after sign-in
- [x] 2.3 Unit tests for the URL and id parsing (FernsyCore, `TopShelfLink`)

## 3. Snapshot and extension

- [x] 3.1 `TopShelfSnapshot` (Codable, FernsyCore) with sections and items; tests for encoding and the 10-item limit
- [x] 3.2 `TVModel` writes the snapshot from Start's rows (Continue Watching, the live row, recordings), debounced by 2 s, copies images into `<group>/TopShelf/`, removes unused ones, calls `topShelfContentDidChange()`; deletes everything on sign-out of the last account
- [x] 3.3 The extension's `ContentProvider` builds `TVTopShelfSectionedContent` from the snapshot (shapes, titles, progress, actions; design 4), `nil` without content; row titles in English and German
- [x] 3.4 tvOS UI test on "Claude Apple TV" with the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, `IPTV_USER=demo`, `IPTV_PASS=demo`, `IPTV_TESTRESUME=movie.500:20:52`, `IPTV_FAVORITES` or the recently watched channels):
  - A new debug MCP tool `top_shelf` returns the written snapshot: a Continue Watching row with movie 500 and the live row.
  - Opening `fernsy-dev://play?item=live:101` (the debug build's scheme) through `xcrun simctl openurl` plays channel 101.

## 4. Static image

- [x] 4.1 `scripts/make-tv-icons.swift` draws the new Top Shelf images (normal and wide, @1x and @2x, release and dev; design 6)
- [x] 4.2 Render two or three variants, show them to the user, keep the chosen one in the assets (2026-10-31: "sunset", with the TV and name centred and the sun moved right)

- [x] 4.3 The app icon's front layer shows the TV alone on the Mac icon's indigo background (back layer), not the Mac icon's whole rounded square, which left a square inside the tvOS icon (noticed by the user, 2026-11-01)

## 5. Verification

- [x] 5.1 Screenshots of the Home Screen on "Claude Apple TV" with Fernsy focused: with content (rows) and signed out (static image); taken with `TopShelfHomeUITests` (Fernsy Dev sits in the simulator's top row)
- [x] 5.2 `scripts/test.sh`, the full Apple TV UI suite (`DEVICE_NAME="Claude Apple TV" scripts/tv-uitest.sh`) and `openspec validate --all --strict` pass. Full run: 53 passed, 14 skipped (Jellyfin and cloud without servers), 1 failed once: `AutoSignInUITests.testProviderLoginSignsInAtLaunch` (the channels step); it passed twice alone and with its whole class
- [x] 5.3 On "Apple TV WZ" (Release) with the user: the rows show their content, a film continues from the Top Shelf, a channel plays, a new position appears after returning to the Home Screen Confirmed by the user on 2026-11-01.
- [x] 5.4 DEVELOPMENT.md: the extension, the App Group, the URL scheme and the `top_shelf` tool

## Workflow follow-up

- Archive on `change/tvos-top-shelf`, merge into `main` and push with the user's consent.
  Release notes: DE "Auf dem Apple TV zeigt Fernsy oben auf dem Home-Bildschirm, was du gerade
  schaust, deine Lieblingssender und neue Aufnahmen – ein Klick spielt sie ab." / EN "On Apple
  TV, Fernsy's Top Shelf shows what you're watching, your favorite channels and new
  recordings – one click plays them."
