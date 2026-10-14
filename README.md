# Fernsy

Native IPTV player for macOS (SwiftUI, FFmpeg, AVSampleBuffer rendering) for Xtream Codes
accounts: live TV with a program guide grid, movies and series. Bundle ID
`de.mobilistics.fernsy`, Apple Silicon only, macOS 27+.

## Build

FFmpeg is not checked in. Build it once (LGPL, decode-only, arm64; needs the Xcode Metal
toolchain: `xcodebuild -downloadComponent MetalToolchain`):

```sh
scripts/build-ffmpeg.sh        # → Vendor/ffmpeg
```

Then open `Fernsy.xcodeproj` or build from the command line. A build phase
(`scripts/embed-ffmpeg.sh`) copies and signs the libraries into the app.

## Release

```sh
UPLOAD=1 scripts/build-appstore.sh          # archive + upload to App Store Connect (build number +1)
VERSION=1.1 UPLOAD=1 scripts/build-appstore.sh
scripts/build-dmg.sh                        # ad-hoc signed DMG in dist/ (outside the App Store)
```

App Store texts, review notes and the privacy policy draft are in `docs/app-store.md`
(`scripts/check-store-texts.py` checks the length limits). `scripts/make-icon.swift`
renders the app icon.

## Development

Debug builds read `IPTV_SERVER`, `IPTV_USER` and `IPTV_PASS` from the environment and then
skip the keychain. Further debug-only switches (`IPTV_AUTOPLAY`, `IPTV_SCENE`, `IPTV_WINDOW`,
`IPTV_TESTNET`, …) are documented where they are read.
