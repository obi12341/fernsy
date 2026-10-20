# Fernsy

Native IPTV player for macOS (SwiftUI, FFmpeg, AVSampleBuffer rendering) for Xtream Codes
accounts: live TV with a program guide grid, timeshift and recordings, movies and series. Bundle ID
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

App Store texts and review notes are in `docs/app-store.md`
(`scripts/check-store-texts.py` checks the length limits). `scripts/make-icon.swift`
renders the app icon.

The product, support, privacy and imprint pages (German and English) live in `website/` and
are published to https://www.fernsy.app/ by `.github/workflows/pages.yml`.

## Demo server

`demo-server/` is a Cloudflare Worker that speaks the Xtream Codes API with fictional,
freely licensed content (sign in with `demo` / `demo` at
https://fernsy-demo.mobilistics.workers.dev). App Review uses it; media files are assets of
the `demo-media` release. Deploy with `demo-server/deploy.sh` (needs `CLOUDFLARE_ACCOUNT_ID`
and `CLOUDFLARE_API_TOKEN`).

## Development

Debug builds read `IPTV_SERVER`, `IPTV_USER` and `IPTV_PASS` from the environment and then
skip the keychain. Further debug-only switches (`IPTV_AUTOPLAY`, `IPTV_SCENE`, `IPTV_WINDOW`,
`IPTV_TESTNET`, …) are documented where they are read.

Live TV runs through a tuner (`Fernsy/Player/LiveTuner.swift`): a headless session receives
the stream, `TimeshiftWriter` remuxes it (FFmpeg's MPEG-TS muxer) into an on-disk
`TimeshiftBuffer`, and the player plays that buffer, so pausing, rewinding and recordings of
the same channel share one connection. Recordings (`Fernsy/Recording/`) copy the buffer into
`~/Movies/Fernsy` and only run while the app is open. For tests use the demo server
(`IPTV_MAXCONN=1` simulates a single-stream account; `IPTV_TESTRECORD=<channel>:<in s>:<s>`
schedules a recording, `IPTV_TESTPAUSE`, `IPTV_TESTGOLIVE`, `IPTV_TESTSEEK` drive timeshift).

## License

Copyright © 2026 mobilistics GmbH

Fernsy is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, version 3 of the
License or (at your option) any later version. See [LICENSE](LICENSE).

The bundled FFmpeg libraries are licensed separately under the LGPL 2.1 or later
(see `scripts/build-ffmpeg.sh`).

Contributions: mobilistics GmbH distributes Fernsy through the Mac App Store, whose terms
are not compatible with the GPL for third-party code. Pull requests can therefore only be
accepted together with a contributor license agreement that allows this.
