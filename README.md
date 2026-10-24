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
keeps the session and the password in the keychain and signs in again by itself when the server
rejects the token (`JellyfinStore.renewSession`); sign-out removes both. Tested with Jellyfin
12.2.0; the routes live in `Fernsy/Jellyfin/JellyfinClient.swift`. Debug builds sign in
without the keychain with `JF_SERVER`, `JF_USER` and `JF_PASS` (`JF_SELFTEST`, `JF_TOKEN`,
`JF_OFFLINE`, `JF_TESTMARK`, `JF_BADPASS`, `JF_TESTRECOVER` are documented where they are read).
Debug builds are a separate Jellyfin device (`jellyfin.deviceId.debug`, name "… (Debug)"):
signing in with the installed app's device id would end its session on the server. Test
clean-ups delete only the debug device. Debug builds should not touch the keychain while the
user is at the Mac – every build has a new signature and macOS asks for access. Write tests against a real
server must back up the user data first and only touch fetched films, series, seasons and
episodes – a played mark on a folder marks everything below it.

Playback (`Fernsy/Jellyfin/JellyfinPlayback.swift`) plays the original file through Fernsy's
own player (direct play, range requests) and reports start, progress and stop to the server,
so resume points and played marks are Jellyfin's. Only codecs the bundled FFmpeg cannot decode
(and Dolby Vision profile 5 on a Mac without a DV decoder), AV1 without a hardware decoder, a
failed direct-play open and external bitmap subtitles use a progressive mkv transcode by the
server; seeking in it
restarts the transcode at the new position. Tone-mapping DV profile 5 needs a server decoder
that reads the DV metadata: on Intel QSV servers enable "Prefer OS native DXVA or VA-API
hardware decoders", otherwise the picture is green/pink in every client. Debug:
`JF_AUTOPLAY=<item id>[:<start s>]`, `JF_BREAKDIRECT=1` (forces the transcode fallback),
`IPTV_TESTSUB=<track id>`, `IPTV_TESTCUES=<srt in the app container>`.

Dolby Vision profile 5 and 8 in MKV/MP4 (any source) is decoded by `Fernsy/Player/DVDecoder.swift`:
a VideoToolbox session created as `dvh1` from the stream's `hvcC` and DV configuration. Only
such a session gives pixel buffers that the display layer shows as Dolby Vision; macOS does the
DV mapping. Profile 7, MPEG-TS streams and Macs without a DV decoder keep FFmpeg's decoder
(HDR10 base layer; profile 5 is then not playable locally). `JF_NODV=1` disables the DV path in
debug builds.

Track preselection (`Fernsy/Player/TrackChooser.swift`) follows Settings › Language &
Subtitles for every source; a pick in the player during a series episode is remembered per
series (`tracks.series`). Debug: `IPTV_AUDIOLANG=<code|system>` and
`IPTV_SUBTITLES=<off|forced|code>` override the settings for one run, `IPTV_TRACKSTORE=test`
keeps the series memory apart, `IPTV_TRACKSELFTEST=1` checks the chooser rules,
`IPTV_AUTOPLAY=episode:<series>:<n>` plays an IPTV episode.

Audio reaches `AVSampleBufferAudioRenderer` in blocks of at least 20 ms: TrueHD frames are
0.83 ms long, and one sample buffer per frame leaves the renderer silent. `IPTV_AUDIOLEVEL=1`
logs peak levels and the renderer state per second, `IPTV_TESTAUDIO=<at s>:<track>,…` switches
audio tracks in a debug run.

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
schedules a recording, `IPTV_TESTPAUSE`, `IPTV_TESTGOLIVE`, `IPTV_TESTSEEK` drive timeshift,
`IPTV_TESTSTALL=<at s>:<s>` holds the playback clock to produce lag,
`IPTV_TESTNODATA=<offline|silent>:<s>` makes tuner connections fail as an offline or silent
channel for that many seconds after the first one; a recording keeps waiting for its channel
until its window ends).
`IPTV_TESTNET` (`drop:`, `stall:`, `close:<s>`) also runs for films: a film's download that ends
before the file does (an idle connection closed during a long pause) continues with a range
request and keeps its buffer; an end more than 60 s before the known duration reloads at the
position instead of finishing (`IPTV_TESTNOCONTINUE=1` switches the first part off to test the
second). Live playback never jumps
on its own: the backlog a provider sends on connect is played (still "LIVE"), and when playback
later falls clearly further behind, it leaves the live state instead of skipping ahead.

Picture in Picture (button in the controls, key P) uses the system's PiP with the player's
display layer; subtitles are not shown in the PiP window. macOS mirrors a sample-buffer PiP
source unscaled (FB22411168), so while PiP runs the layer lives in an invisible window that
follows the PiP window's size (`Fernsy/Player/PictureInPicture.swift`).
`IPTV_TESTPIP=<s>[:back:<s>]` starts PiP and optionally returns to the player; closing has to be
tested with the PiP window's close button (ending PiP from code always counts as "back").
Starting something from the main window while PiP runs plays it in the PiP window, with a loading
picture rendered into the video until its first frame (`IPTV_TESTSWITCH=<s>:<live|movie>:<id>`
starts an item the way the main window does, `IPTV_TESTSLOWSTART=<s>` delays every start,
`IPTV_TESTNOVIDEO=1` treats later items as radio, which ends PiP).

The toolbar search searches everything at once – channels, films, series, recordings and the
Jellyfin libraries – from a local index (`Fernsy/App/SearchIndex.swift`, rebuilt in the
background when a source changes; about 20 ms per query for 50,000 entries). Only Live TV's Edit
mode keeps it as a filter of the channel list. `IPTV_TESTSEARCH=<query>[|<query>…]` types
queries once the catalog is loaded, one every 4 s.

The player window moves when the picture is dragged (`VideoSurfaceView.mouseDown` hands single
clicks to `performDrag`); a click still shows the controls, a double-click toggles full screen.

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
