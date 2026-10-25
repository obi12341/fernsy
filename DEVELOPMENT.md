# Fernsy – developer documentation

Native IPTV player for macOS (SwiftUI, FFmpeg, AVSampleBuffer rendering) for Xtream Codes
accounts: live TV with a program guide grid, timeshift and recordings, movies and series –
plus a Jellyfin account for browsing and playing films and series. Bundle ID
`de.mobilistics.fernsy`, Apple Silicon only, macOS 27+.

This file is for contributors and maintainers: building, releases, update signing, the demo
server and the debug switches. The product description is in [README.md](README.md).

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
are published to https://www.fernsy.app/ by `.github/workflows/pages.yml` on every push to
main. The images on the home page are rendered from the mockups of the Claude Design project
"Fernsy Redesign" (headless Chrome, 2×, WebP); they are not app screenshots. The English
images (`en-*.webp`) come from copies of the mockups with translated texts.

### Releases and nightlies via GitHub Actions

`.github/workflows/release.yml` builds on the GitHub-hosted `xcode-27` runner (macOS 27, public
preview) with Xcode 27.1. The version comes from the tag, the build number from the commit
count (`git rev-list --count`); neither is written back to the project.

- **Tag `vX.Y` or `vX.Y.Z` on main.** This builds two things in parallel:
  - the notarized DMG;
  - the App Store build, signed with Apple's cloud signing through the API key and uploaded
    to App Store Connect.

  Only when both work does it publish the release "Fernsy X.Y" with `Fernsy.dmg` and
  `Fernsy-X.Y.dmg`. Submitting for review stays a manual step in App Store Connect. A release
  created by hand in the GitHub web interface keeps its text and gets the DMGs attached.
  Otherwise the release text comes from the commits (see "Release notes" below). The website's
  download button links to `releases/latest/download/Fernsy.dmg`.
- **Nightly.** Every night at 02:00 UTC, if main changed, it builds the notarized DMG. It
  replaces the single pre-release "Nightly" (tag `nightly`) with `Fernsy-Nightly.dmg`. A
  nightly has no release version: it is `nightly-<commit date>` with the commit count as build
  number, and the text lists the release notes and all commits since the last release. Nightlies
  are the same app (bundle ID, data) and install over Fernsy. Pre-releases never become
  "latest".
- **Manual runs:**
  - `gh workflow run release.yml` builds a nightly now;
  - `-f channel=appstore-test` archives and exports the App Store build without uploading it.

**Release notes.** A commit with a change users notice ends with one sentence per language
as trailers, next to `Co-Authored-By`:

```
Release-Note-de: Aufnahmen lassen sich während einer Aufnahme wieder öffnen.
Release-Note-en: Recordings open again while a recording runs.
```

Internal commits (task marks, archives, CI, refactoring, specs) carry none. A commit may carry
several pairs. `scripts/release-notes.sh` collects them since the previous release tag (for a
nightly: since the last one), oldest first, without duplicates. They become the German and
English sections of the release text and Sparkle's update notes in both languages
(`scripts/appcast-notes.py`). If a release range has no trailers, the run shows a warning and
uses the commit subjects instead, without "Mark …", "Archive …" and merges.

The DMG steps are:
1. build LGPL FFmpeg, cached;
2. sign with Developer ID and the hardened runtime;
3. run the smoke test;
4. notarize, and staple;
5. check the result with Gatekeeper.

One-time setup:
1. **Certificate.** In the Apple Developer account (team B8YT7FNB66, only the Account Holder
   can do this), create a "Developer ID Application" certificate. Export it with its private
   key from Keychain Access as a .p12 with a password.
2. **API key.** In App Store Connect › Users and Access › Integrations, create a team API key
   with the **Admin** role. Cloud signing for the App Store build needs Admin; notarization
   alone would need only Developer. Download the .p8 and note the key ID and issuer ID.
3. **Repository secrets** (Settings › Secrets and variables › Actions):
   - `DEVELOPER_ID_P12`: `base64 -i DeveloperID.p12 | gh secret set DEVELOPER_ID_P12`;
   - `DEVELOPER_ID_P12_PASSWORD`: set it in the web interface;
   - `NOTARY_KEY_P8`: `base64 -i AuthKey_XXXX.p8 | gh secret set NOTARY_KEY_P8`;
   - `NOTARY_KEY_ID` and `NOTARY_ISSUER`.

### Updates of the DMG build (Sparkle)

The DMG is built from the target **"Fernsy Direct"**. It has the same sources and bundle ID
as "Fernsy", plus the Sparkle 2 package, `DIRECT_DISTRIBUTION`,
`Config/Info-Direct.plist` and `Config/Fernsy-Direct.entitlements`. The App Store build
("Fernsy") contains no updater. New files are picked up by both targets through the
synchronized `Fernsy/` folder.

The release workflow attaches a signed `appcast.xml` to every release and to the nightly. The
app reads `releases/latest/download/appcast.xml`, or the nightly's feed when "Nightly-Builds
erhalten" is on. Updates never relaunch Fernsy while a recording runs or starts within 30
minutes.

One-time key setup:
1. Download Sparkle's tools (`Sparkle-2.10.0.tar.xz` from the Sparkle releases) and run
   `bin/generate_keys`. It stores the private key in your keychain and prints the public key.
2. Export the private key with `bin/generate_keys -x sparkle-private.txt`, then run
   `gh secret set SPARKLE_ED_PRIVATE_KEY < sparkle-private.txt`, and delete the file.
3. Put the public key into the build setting `SPARKLE_PUBLIC_ED_KEY` of the "Fernsy Direct"
   target.

Keep the private key safe. Without it no update can be signed, and a new key means one manual
update for every user.

Debug switches: `IPTV_UPDATEFEED=<url>` runs Sparkle in a debug build against a test feed.
Without it, Sparkle stays off in debug builds, because they share its settings with the
installed app. `IPTV_TESTUPDATEHOLD=1` logs every 10 s whether an update would wait for
recordings.

Do not push a release tag before the previous version is approved in the App Store. A tag
uploads to App Store Connect.

Locally the same scripts still work:
- `SIGN_IDENTITY="Developer ID Application: …" NOTARY_KEY=AuthKey.p8 NOTARY_KEY_ID=… NOTARY_ISSUER=… scripts/build-dmg.sh`
  (or with a `NOTARY_PROFILE`);
- `UPLOAD=1 scripts/build-appstore.sh` with the Xcode account.

Both take `BUILD_VERSION`/`BUILD_NUMBER` for one build without changing the project.

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

"Beim Anmelden öffnen" (Settings › Aufnahmen) registers Fernsy with `SMAppService.mainApp`;
opened at login (Apple Event `keyAELaunchedAsLogInItem`), Fernsy closes its library window and
runs in the menu bar (`LoginItem`, `MenuBarSupport.startWithoutWindow`). Debug builds never
register a login item: `IPTV_TESTLOGINITEM=<enabled|approval|off>` fakes the status macOS
reports, `IPTV_TESTLOGINLAUNCH=1` starts as if opened at login.

Every build writes an event log (`Fernsy/App/AppLog.swift`): levels error, warning, info and
detail, one category per area. It is kept in memory and in `current.log` and `previous.log`
(this launch and the previous one, 4 MB each at most) under
`~/Library/Containers/de.mobilistics.fernsy/Data/Library/Caches/Fernsy/logs/`. Window › Log
(⌥⌘L) shows it, and the window can copy it or save it as a text file. Saving needs
`com.apple.security.files.user-selected.read-write` (review note: "Saves the app's own
diagnostic log where the user chooses"). Passwords, tokens and Xtream path or query
credentials are replaced by "•••" before an entry is stored. Debug builds also write every
entry to stderr. `debugLog` is left for `[test]` hooks only. `IPTV_TESTLOG=1` opens the log
window (`previous` shows the previous launch), and `IPTV_LOGSELFTEST=1` checks the redaction.

Shared design building blocks live in `Fernsy/Views/Design/` (colour tokens, `LogoTile`,
`StatusBadge`); the accent is `AccentColor` in the asset catalog. Debug switches:
`IPTV_APPEARANCE=light|dark` runs in that appearance without changing the system,
`IPTV_LOGOTONETEST=1` checks the logo tile's tone detection and initials,
`IPTV_TESTNOPOSTER=1` shows every poster card's placeholder.
Channel and category names are cleaned by `Fernsy/Xtream/ChannelName.swift` (country and
quality tags, decoration removed; the delivered name stays in "Senderinfo" and in the search
key). `IPTV_NAMETEST=1` runs its examples, `IPTV_TESTINFO=<channel id>` opens a channel's
info, `IPTV_LIVEMODE=list|guide` picks the Live TV view for one run.
Live TV: `IPTV_SELECT=<id>` selects a channel (detail pane), `IPTV_TESTSCHEDULE=1` then
schedules its second upcoming show, `IPTV_TESTCATALOGFAIL=1` makes the catalog refresh fail
(the provider-unreachable notice over the cached list). `IPTV_CLOCKOFFSET=<s>` shifts "now" in
the rows and the detail pane only (to see a show change without waiting for one);
`IPTV_EPGRECHECK=<s>` sets how often a visible row checks its programme (default 5 min) and
`IPTV_EPGSTALE=1` treats every programme as stale, so each check downloads it again.
Player channel list: `IPTV_TESTCHANNELLIST=<s>[:<key>,…]` opens it after s seconds and feeds the
keys (`down`, `up`, `pagedown`, `return`, `esc`, `l`, `category:<id>`) one per second through
the player's own key handling.
Youth protection, in memory only: `IPTV_TESTADULT=<id,…>` treats channels as adult (the demo
has none), `IPTV_RECENT=<id,…>` sets "Zuletzt gesehen", `IPTV_SHOWADULT=0|1` and
`IPTV_ADULTRECENT=0|1` set both settings, `IPTV_TESTUNRECENT=<id>` removes a channel from
the history like the context menu.
IPTV films and series (Settings › Konten), in memory only: `IPTV_SHOWMOVIES=0|1` and
`IPTV_SHOWSERIES=0|1` set both switches, `IPTV_TESTSWITCHMEDIA=<s>:<movies|series>:<0|1>,…`
flips them s seconds after the live catalog loaded, as the Settings switches do.
Guide: `IPTV_TESTNOEPG=<id>` gives that channel no listings, `IPTV_GUIDEDAY=<n>` and
`IPTV_GUIDETIME=<hh:mm>` jump to a day and time, `IPTV_GUIDESELECT=<id>:<n>` selects that
channel's n-th upcoming show.
Films and series: resume positions and watched flags stay in memory in keychain-less test
runs; `IPTV_TESTRESUME=<key>:<pos s>:<dur s>,…` and `IPTV_TESTWATCHED=<key>,…` (keys like
`movie.500`, `episode.00100`) set them for one run.
Sign-in and Settings: `IPTV_TESTLOGIN=<iptv|jellyfin>|<server>|<user>|<pass>` fills the login
screen's form and submits it (without `IPTV_SERVER`; use the demo server or an unreachable
address such as `http://127.0.0.1:9`), `IPTV_TESTSETTINGS=<accounts|playback|recordings|youthProtection>`
opens Settings on that tab once the catalog is loaded.

Live TV runs through a tuner (`Fernsy/Player/LiveTuner.swift`): a headless session receives
the stream, `TimeshiftWriter` remuxes it (FFmpeg's MPEG-TS muxer) into an on-disk
`TimeshiftBuffer`, and the player plays that buffer, so pausing, rewinding and recordings of
the same channel share one connection. Recordings (`Fernsy/Recording/`) copy the buffer into
`~/Movies/Fernsy` and only run while the app is open. For tests use the demo server
(`IPTV_MAXCONN=1` simulates a single-stream account;
`IPTV_TESTRECORD=<channel>:<in s>:<s>[:<before min>:<after min>],…` plans recordings in that
order, refused or with shortened padding as the stream limit requires; `IPTV_PLANTEST=1` runs
the plan calculation's examples (`RecordingPlan`), `IPTV_AWAKEHOURS=<hours|0|off>` sets "Mac wach halten" in memory
(0 = always while a recording is scheduled, off = never), `IPTV_TESTPAUSE`, `IPTV_TESTGOLIVE`, `IPTV_TESTSEEK` drive timeshift,
`IPTV_TESTSTALL=<at s>:<s>` holds the playback clock to produce lag,
`IPTV_TESTNODATA=<offline|silent>:<s>` makes tuner connections fail as an offline or silent
channel for that many seconds after the first one; a recording keeps waiting for its channel
until its window ends).
`IPTV_TESTNET` (`drop:`, `stall:`, `close:<s>`; for live also `forbid:<s>`, the next edge
reconnect gets a 403, and `flaky:<s>`, dropping again 6 s after the reconnect) (`IPTV_LIVELEAD=<s>`
starts live closer to the newest data for the dry-player rule) also runs for films: a film's download that ends
before the file does (an idle connection closed during a long pause) continues with a range
request and keeps its buffer; an end more than 60 s before the known duration reloads at the
position instead of finishing (`IPTV_TESTNOCONTINUE=1` switches the first part off to test the
second). Live playback never jumps
on its own: the backlog a provider sends on connect is played (still "LIVE"), and when playback
later falls clearly further behind, it leaves the live state instead of skipping ahead.

The MCP server (`Fernsy/MCP/`, Settings › Assistenten) answers MCP over Streamable HTTP on
`http://127.0.0.1:52323/mcp` (debug builds: port 52324), JSON responses only, with the bearer
token from Settings (keychain). It needs `com.apple.security.network.server` (review note: local
MCP server on 127.0.0.1 for the user's own AI assistant, off by default). Requests with an
`Origin` header or a foreign `Host` are refused. Tools: `MCPTools.definitions`. Debug builds keep
everything in memory: `IPTV_MCP=1` switches the server on, `IPTV_MCPTOKEN=<token>` sets the
token, `IPTV_MCPREGEN=<s>` creates a new token after s seconds.
"Zu Claude Desktop hinzufügen …" builds a desktop extension (`MCPDesktopExtension`, `.mcpb`
manifest 0.3: a dependency-free Node bridge from stdio to the endpoint, the token directly in
`mcp_config.env` because Claude Desktop ignores the default of a sensitive `user_config` field
and then never starts the server; version x.y.z, `0.0.<build>` for nightlies) in the temporary directory, zipped with `ditto`, and opens it with Claude
Desktop (`com.anthropic.claudefordesktop`), else offers to save it. `IPTV_MCPBUNDLE=1` builds it
at launch and logs the path, `IPTV_MCPADDCLAUDE=<s>` runs the button after s seconds,
`IPTV_TESTNOCLAUDE=1` acts as if Claude Desktop were missing, `IPTV_MCPVERSION=<version>` fakes the
app version for the manifest.

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

The renderers are fed through their macOS 27 receivers (`Fernsy/Player/RendererSinks.swift`).
Every enqueue reports when the video decoder needs a flush (after sleep/wake, a display or GPU
change, or broken data): the player then resumes at the current position from the next key
frame, and gives up after three recoveries in 30 s. Frames that failed to decode are counted
in the technical info ("Decodierfehler"). A suggested audio flush (output device changed)
refills the audio. Test switches:
- `IPTV_TESTFLUSHREQUIRED=<s>[:<count>]` simulates "needs a flush" s seconds after the first
  frame, count times, 3 s apart;
- `IPTV_TESTDECODEFAIL=<n>` reports n failed frames after 5 s.

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
