# Fernsy

Native IPTV player for macOS (SwiftUI, FFmpeg, AVSampleBuffer rendering) for Xtream Codes
accounts: live TV with a program guide grid, timeshift and recordings, movies and series –
plus a Jellyfin account for browsing and playing films and series. Bundle ID
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

App Store texts and review notes are kept locally in `docs/app-store.md`, which is not
part of the repository (`docs/` is git-ignored); `scripts/check-store-texts.py` checks
their length limits. `scripts/make-icon.swift`
renders the app icon.

The product, support, privacy and imprint pages (German and English) live in `website/` and
are published to https://www.fernsy.app/ by `.github/workflows/pages.yml`.

## Demo server

`demo-server/` is a Cloudflare Worker that speaks the Xtream Codes API with fictional,
freely licensed content (sign in with `demo` / `demo` at
https://fernsy-demo.mobilistics.workers.dev). App Review uses it; media files are assets of
the `demo-media` release. Deploy with `demo-server/deploy.sh` (needs `CLOUDFLARE_ACCOUNT_ID`
and `CLOUDFLARE_API_TOKEN`).

## Jellyfin

A Jellyfin account can be added next to the IPTV account (login screen or Settings). Fernsy
stores only the access token in the keychain, never the password. Tested with Jellyfin
12.2.0; the routes live in `Fernsy/Jellyfin/JellyfinClient.swift`. Debug builds sign in
without the keychain with `JF_SERVER`, `JF_USER` and `JF_PASS` (`JF_SELFTEST`, `JF_TOKEN`,
`JF_OFFLINE`, `JF_TESTMARK` are documented where they are read). Write tests against a real
server must back up the user data first and only touch fetched films, series, seasons and
episodes – a played mark on a folder marks everything below it.

Playback (`Fernsy/Jellyfin/JellyfinPlayback.swift`) plays the original file through Fernsy's
own player (direct play, range requests) and reports start, progress and stop to the server,
so resume points and played marks are Jellyfin's. Only Dolby Vision profile 5, codecs the
bundled FFmpeg cannot decode, AV1 without a hardware decoder, a failed direct-play open and
external bitmap subtitles use a progressive mkv transcode by the server; seeking in it
restarts the transcode at the new position. Tone-mapping DV profile 5 needs a server decoder
that reads the DV metadata: on Intel QSV servers enable "Prefer OS native DXVA or VA-API
hardware decoders", otherwise the picture is green/pink in every client. Debug:
`JF_AUTOPLAY=<item id>[:<start s>]`, `JF_BREAKDIRECT=1` (forces the transcode fallback),
`IPTV_TESTSUB=<track id>`, `IPTV_TESTCUES=<srt in the app container>`.

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
