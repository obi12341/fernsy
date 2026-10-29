# Fernsy – developer documentation

Native IPTV player for macOS (SwiftUI, FFmpeg, AVSampleBuffer rendering) for Xtream Codes
accounts: live TV with a program guide grid, timeshift and recordings, movies and series –
plus a Jellyfin account for browsing and playing films and series. Bundle ID
`de.mobilistics.fernsy`, Apple Silicon only, macOS 27+.

This file is for contributors and maintainers: building, releases, update signing, the demo
server and the debug switches. The product description is in [README.md](README.md).

## Build

FFmpeg is not checked in. Build it once (LGPL, decode plus the MPEG-TS muxer, arm64; needs the
Xcode Metal toolchain: `xcodebuild -downloadComponent MetalToolchain` and, for the Apple TV
slices, the tvOS SDK):

```sh
scripts/build-ffmpeg.sh                  # macOS, tvOS and tvOS simulator, about 10 min
PLATFORMS=macos scripts/build-ffmpeg.sh  # only the Mac slice
```

It writes one XCFramework of dynamic framework bundles per library (avutil, swresample,
swscale, avcodec, avformat, avfilter) to `Packages/FernsyPlayer/Frameworks/`, the headers to
`Packages/FernsyPlayer/Sources/CFFShim/include/`, and `BUILDINFO.txt` (source URL and configure
lines per platform, the LGPL source offer) with `COPYING.LGPLv2.1`. All of it is git-ignored.
Configure refuses to continue when a GPL or nonfree component would be enabled. Frameworks, not
loose dylibs: tvOS accepts nothing else, and the user can still replace them (LGPL).

The package `Packages/FernsyPlayer` (depends on `Packages/FernsyCore`) holds playback: the C
bridge `CFFShim`, the FFmpeg binary targets and the `FernsyPlayer` library (byte sources,
session, tuner and pool, timeshift buffer and writer, audio tap, renderers, `PlayerEngine`). Its
strings use `bundle: .module` and its own catalog. The video surface and picture in picture
stay in each app. Both app targets link `FernsyPlayer` and embed the six frameworks with
"Embed Frameworks" (signed on copy). Then open `Fernsy.xcodeproj` or build from the command line.

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

Track preselection (`Packages/FernsyCore/Sources/FernsyCore/TrackChooser.swift`) follows Settings › Language &
Subtitles for every source; a pick in the player during a series episode is remembered per
series (`tracks.series`). Debug: `IPTV_AUDIOLANG=<code|system>` and
`IPTV_SUBTITLES=<off|forced|code>` override the settings for one run, `IPTV_TRACKSTORE=test`
keeps the series memory apart (the chooser rules are tests: `TrackChooserTests`),
`IPTV_AUTOPLAY=episode:<series>:<n>` plays an IPTV episode. `IPTV_AUTOPLAY=archive:<channel>` plays the show that began about a day ago from that channel's archive (catch-up; the demo server's channels 101–103 have one).

Audio reaches `AVSampleBufferAudioRenderer` in blocks of at least 20 ms: TrueHD frames are
0.83 ms long, and one sample buffer per frame leaves the renderer silent. `IPTV_AUDIOLEVEL=1`
logs peak levels and the renderer state per second, `IPTV_TESTAUDIO=<at s>:<track>,…` switches
audio tracks in a debug run.

## Development

Debug builds read `IPTV_SERVER`, `IPTV_USER` and `IPTV_PASS` from the environment and then
skip the keychain; an empty `IPTV_SERVER=` starts without an account. Further debug-only switches (`IPTV_AUTOPLAY`, `IPTV_SCENE`, `IPTV_WINDOW`,
`IPTV_TESTNET`, …) are documented where they are read.

### Dev build next to the installed app

Debug builds are "Fernsy Dev": bundle id `de.mobilistics.fernsy.dev`, an icon with a "DEV"
band (`swift scripts/make-dev-icon.swift` after icon changes), the product name stays
`Fernsy`. They have their own container (`~/Library/Containers/de.mobilistics.fernsy.dev`),
defaults, keychain service and system registrations, and record into `~/Movies/Fernsy Dev`, so
they never see or change the installed app's accounts, settings or recordings. On top:

- Quiet: they start muted (`IPTV_SOUND=1` for sound), never store the volume, and never come
  to the front (`AppActivation`; `IPTV_ACTIVATE=1` to allow it). Window screenshots by window
  id work behind other windows.
- Xtream streams (live, films, episodes, catch-up) only from the demo worker, `127.0.0.1` or
  `localhost`; anything else fails with "Debug-Build: echte Anbieter nur mit
  IPTV_ALLOWREAL=1" before a request is made (`PlayerError.debugAllows`). Catalog and EPG
  requests stay allowed.
- `scripts/dev-run.sh [--no-build] [--log <file>] [KEY=value …]` builds at background priority
  (`taskpolicy -b`) and starts the dev build with `open -g` against the demo server.
- `scripts/dev-copy-prod.sh --list | --account <n> | --settings` copies an account folder of
  the installed app (as `copied-<n>`, scheduled and running recordings set to skipped) or an
  allow-list of settings into the dev container; it only reads the installed app's container
  and copies no keychain items. `IPTV_COPIEDACCOUNT=copied-<n>` opens such a copy offline:
  cached catalog and recordings list, no requests, no streams. Recording files stay in
  `~/Movies/Fernsy` and are not played from a copy.

"Beim Anmelden öffnen" (Settings › Aufnahmen) registers Fernsy with `SMAppService.mainApp`;
opened at login (Apple Event `keyAELaunchedAsLogInItem`), Fernsy closes its library window and
runs in the menu bar (`LoginItem`, `MenuBarSupport.startWithoutWindow`). Debug builds never
register a login item: `IPTV_TESTLOGINITEM=<enabled|approval|off>` fakes the status macOS
reports, `IPTV_TESTLOGINLAUNCH=1` starts as if opened at login.

Every build writes an event log (`Packages/FernsyCore/Sources/FernsyCore/AppLog.swift`): levels error, warning, info and
detail, one category per area. It is kept in memory and in `current.log` and `previous.log`
(this launch and the previous one, 4 MB each at most) under
`~/Library/Containers/de.mobilistics.fernsy/Data/Library/Caches/Fernsy/logs/`. Window › Log
(⌥⌘L) shows it, and the window can copy it or save it as a text file. Saving needs
`com.apple.security.files.user-selected.read-write` (review note: "Saves the app's own
diagnostic log where the user chooses"). Passwords, tokens and Xtream path or query
credentials are replaced by "•••" before an entry is stored. Debug builds also write every
entry to stderr. `debugLog` is left for `[test]` hooks only. `IPTV_TESTLOG=1` opens the log
window (`previous` shows the previous launch); the redaction is tested in `AppLogTests`.

Shared design building blocks live in `Fernsy/Views/Design/` (colour tokens, `LogoTile`,
`StatusBadge`); the accent is `AccentColor` in the asset catalog. Debug switches:
`IPTV_APPEARANCE=light|dark` runs in that appearance without changing the system,
`IPTV_LOGOTONETEST=1` checks the logo tile's tone detection and initials,
`IPTV_TESTNOPOSTER=1` shows every poster card's placeholder.
Channel and category names are cleaned by `Packages/FernsyCore/Sources/FernsyCore/ChannelName.swift` (country and
quality tags, decoration removed; the delivered name stays in "Senderinfo" and in the search
key; its examples are `ChannelNameTests`), `IPTV_TESTINFO=<channel id>` opens a channel's
info, `IPTV_LIVEMODE=list|guide` picks the Live TV view for one run.
Live TV: `IPTV_SELECT=<id>` selects a channel (detail pane), `IPTV_TESTSCHEDULE=1` then
schedules its second upcoming show, `IPTV_TESTCATALOGFAIL=1` makes the catalog refresh fail
(the provider-unreachable notice over the cached list). `IPTV_CLOCKOFFSET=<s>` shifts "now" in
the rows and the detail pane only (to see a show change without waiting for one);
`IPTV_EPGRECHECK=<s>` sets how often a visible row checks its programme (default 5 min) and
`IPTV_EPGSTALE=1` treats every programme as stale, so each check downloads it again. `IPTV_TESTEPGDELAY=<s>` makes listings arrive that much later (loading rows in the guide's UI tests).
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
order, refused or with shortened padding as the stream limit requires (the plan calculation's examples are
`RecordingPlanTests`), `IPTV_AWAKEHOURS=<hours|0|off>` sets "Mac wach halten" in memory
(0 = always while a recording is scheduled, off = never), `IPTV_TESTPAUSE`, `IPTV_TESTGOLIVE`, `IPTV_TESTSEEK` drive timeshift,
`IPTV_TESTSTALL=<at s>:<s>` holds the playback clock to produce lag,
`IPTV_TESTDRAG=<at s>:<to fraction>[:<hold s>],…` drags the player's timeline knob (live or film)
with mouse events posted into the app only (the pointer does not move; hover marks need the real
pointer), `IPTV_TESTTIMELINE=<inset>` shows system sliders with marks at that knob inset instead
of the library (to re-measure `TimelineSlider.knobInset` after a macOS update),
`IPTV_SECTION=<live|recordings|…>` opens the library on that section,
`IPTV_TESTNODATA=<offline|silent>:<s>` makes tuner connections fail as an offline or silent
channel for that many seconds after the first one; a recording keeps waiting for its channel
until its window ends).
`IPTV_TESTNET` (`drop:`, `stall:`, `close:<s>`; for live also `forbid:<s>`, the next edge
reconnect gets a 403, `flaky:<s>`, dropping again 6 s after the reconnect, and `trickle:<s>`,
the connection delivering only `IPTV_TRICKLEKBIT` kbit/s (default 300) until the next reconnect,
for the slow-delivery rule (`IPTV_TRICKLEMORE=<n|all>`: that many later connections as well, so the
player runs dry and shows the provider card, or a recording misses content and lists the gap;
`IPTV_TESTCLOCK=1` logs the content clock the rule measures every 2 s); `IPTV_TESTNOPATH=1` acts as if macOS had no network, for the
"Keine Internetverbindung" card) (`IPTV_LIVELEAD=<s>`
starts live closer to the newest data for the dry-player rule) also runs for films: a film's download that ends
before the file does (an idle connection closed during a long pause) continues with a range
request and keeps its buffer; an end more than 60 s before the known duration reloads at the
position instead of finishing (`IPTV_TESTNOCONTINUE=1` switches the first part off to test the
second). A film's download is held at 24 MB buffered ahead and resumes at 8 MB; every 15 s a
keep-alive lets it run briefly (up to 48 MB ahead): the 30 s request timeout also runs while the task is held, and a
timed-out hold continues on a new connection whose seam plays as an audio gap
(`IPTV_TESTWATER=<high KB>:<low KB>[:<timeout s>]` sets smaller marks and a shorter timeout, the
cap being half of it, so the demo film, 52 s and 14.6 MB, is held long enough to time out;
holds and resumes are logged at detail level). Live playback never jumps
on its own: the backlog a provider sends on connect is played (still "LIVE"), and when playback
later falls clearly further behind, it leaves the live state instead of skipping ahead.

The MCP server (`Fernsy/MCP/`, Settings › Assistenten) answers MCP over Streamable HTTP on
`http://127.0.0.1:52323/mcp` (debug builds: port 52324), JSON responses only, with the bearer
token from Settings (keychain). It needs `com.apple.security.network.server` (review note: local
MCP server on 127.0.0.1 for the user's own AI assistant, off by default). Requests with an
`Origin` header or a foreign `Host` are refused. Tools: `MCPTools.definitions`. `now_playing` reads the open player's `PlayerEngine` (`AppModel.playerEngine`,
weak, set by `PlayerScreen`) for position, duration, remaining time and state; `item_info` and
`recently_watched` add runtimes (Jellyfin ticks, the resume store, `get_vod_info`'s duration).
`get_log` and `playback_diagnostics` read the redacted event log (`AppLog.query`) and the player's
`PlaybackStats`; the log leaves the app only through this local server, when it is on.
`pause`, `resume` and `seek` drive the open player's `PlayerEngine` with the app's own limits;
`now_playing` reports the timeshift range of a live channel (`rewind_available_seconds`, `buffer_starts_at`).
After a Jellyfin episode `now_playing` names the `next` one and its countdown (`starts_in_seconds`,
owned by `JellyfinPlayback.autoplayAt`, reached through the weak `AppModel.jellyfinPlayback`);
`item_info` adds `previous_*`/`next_*` neighbours and `list_episodes` lists seasons or one season's
episodes (both from `Shows/{id}/Episodes`, specials only next to specials). The end of a Jellyfin
item is reported as a stop right away (`JellyfinPlayback.reportEnd`), so Next Up moves on while
the countdown runs; `JF_TESTCANCELNEXT=1` cancels the countdown at the end.
Scene search: `snapshot` encodes `PlayerEngine.lastPicture`; `frames` runs `FrameGrabber` (own
FFmpeg context over a fresh `FileByteSource`, `TimeshiftBuffer` reader or Jellyfin direct-stream
`HTTPByteSource`; keyframe per tile, corrupt ones skipped) and `StillImage.contactSheet`;
`get_subtitles` returns the Jellyfin text track the assistant picked from `item_info`'s
`subtitle_tracks` (default: the playing or the only text track) via `subtitleSRT`, which has its
own 120 s timeout because the server extracts an embedded track on the first request. Images go out as MCP image
content (`MCPTools.imageKey`), JPEG through ImageIO. IPTV films and episodes are refused by
`frames` (second stream). A changed tool list
reaches Claude Desktop only after the extension is installed again. Debug builds keep
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

Siri, Spotlight and Shortcuts use App Intents (`Fernsy/Intents/`): `ChannelEntity` (indexed in
Spotlight's semantic index, visible channels only), `ShowEntity`, five App Shortcuts with English
phrases in code and German ones in `Fernsy/AppShortcuts.xcstrings`; the actions themselves are
`FernsyActions`, shared with the MCP tools. Debug builds neither index nor donate unless
`IPTV_SIRIINDEX=1`. `IPTV_TESTINTENT=<step>|…` runs the intents' actions once the catalog is
loaded and logs the answers (`query:<text>`, `suggested`, `play:<id>`, `whatson`, `find:<text>`,
`record[:<id>]`, `recordshow:<channel>:<epoch>`, `stop`, `open:<id>`, `search:<text>`).
Siri AI (macOS 27) ignores App Shortcut phrases by voice and only uses schema intents: Fernsy has
`OpenChannelIntent` (`.system.open`, opening a channel plays it) and `SearchFernsyIntent`
(`.system.searchInApp`, fills the library's search). Everything else is for MCP, Shortcuts and
Spotlight.

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
While the player is in full screen, `LibraryWindows` orders the library windows out, so
activating Fernsy (⌘-Tab, Dock) switches to the full-screen Space instead of showing the library
on the desktop (macOS only switches Spaces when the app has no window on the current one). They
come back behind the player when it leaves full screen or closes; `showLibrary` (menu bar, Siri)
takes a hidden one instead of opening a second. `IPTV_TESTFS=1` enters, leaves and re-enters
full screen.

### iCloud sync

Settings and choices sync through the iCloud key-value store, logins through CloudKit
(icloud-sync; `FernsyCore/SyncStore.swift`, `LoginSync.swift`). What syncs: favourites,
recently watched, track languages, recording padding (UserDefaults keys, each stamped in
`sync.t.<key>`), resume positions (one `resume` entry, merged per item), and per account the
hidden channels and pinned categories (`a.<hash>.visibility`, `.pinned`). Logins are records
`xtream` and `jellyfin` (server, user, password in `encryptedValues`) in the private database
of `iCloud.<bundle id>`; Jellyfin sessions never sync.

- **Signing.** iCloud needs a provisioning profile, so debug builds are signed automatically
  with the team's Apple Development certificate (not ad hoc). `dev-run.sh` passes
  `-allowProvisioningUpdates`; device builds of the Apple TV app need it too. Simulator builds
  need no profile. Containers: `iCloud.de.mobilistics.fernsy` (release) and
  `iCloud.de.mobilistics.fernsy.dev` (debug); debug builds sync only with debug builds.
- **DMG.** A signed DMG embeds the Developer ID profile "Fernsy Direct Developer ID", which
  `scripts/direct-profile.swift` finds or creates with the App Store Connect API key
  (`ASC_KEY`, `ASC_KEY_ID`, `ASC_ISSUER`; `build-dmg.sh` passes the notary key). An ad-hoc DMG
  leaves the iCloud entitlements out and keeps its settings on the Mac. `release.yml`'s channel
  `dmg-test` builds, notarizes and checks the DMG without publishing it.
- **CloudKit schema.** Debug builds create the record type `Login` in the Development
  environment on first save. Before a release uses it, deploy the schema to Production in the
  CloudKit console (container `iCloud.de.mobilistics.fernsy`, "Deploy Schema Changes").
- **Test runs.** Keychain-less runs (`FERNSY_NO_KEYCHAIN`, UI tests) sync nothing unless
  `IPTV_SYNC=1`, so tests never touch the developer's iCloud. Apple TV debug builds:
  `IPTV_TESTDEFAULTS=<key>=<value>,…` changes settings at launch as if made there. Both apps'
  debug builds: `IPTV_TESTICLOUDLOGIN=demo|demo-wrong|jellyfin` puts that login (demo server,
  demo server with a wrong password, local test Jellyfin) in memory as if found in iCloud, so a
  launch without an account signs in with it. The log notes what is sent and taken ("iCloud: …").
- **Sign-in at launch.** Without an account, both apps look in iCloud for up to 10 s, showing
  "Signing in …", and sign in with what they find; the welcome or login screen shows only when
  nothing worked. Signing out offers the iCloud login on that screen for the rest of the session.
- **Pitfalls.** iCloud Keychain does not sync app items to tvOS (hence CloudKit for logins).
  `ubiquityIdentityToken` is nil on tvOS (no iCloud Drive); availability comes from
  `CKContainer.accountStatus()`. The key-value store's keys are limited to 64 bytes (account
  values use a hash of the account key).

### Apple TV

The target "Fernsy TV" (tvOS 27, arm64, sources in `FernsyTV/`) is the Apple TV app. It links
`FernsyCore` and `FernsyPlayer` like the Mac app and has the same bundle ids (universal
purchase): Release `de.mobilistics.fernsy` ("Fernsy"), Debug `de.mobilistics.fernsy.dev`
("Fernsy Dev", icon with the DEV band). Icons: `swift scripts/make-tv-icons.swift`, a stand-in
built from the Mac icon. It is not shipped yet.

`TVModel` (`FernsyTV/Model/`) is everything the screens read: the account (sign-in via
`XtreamClient`, keychain via `CredentialStore`), the live categories and channels (a JSON cache
in Caches, which tvOS may delete), the guide (`EPGStore`), playback (`TunerPool`,
`PlayerEngine`; timeshift capped at 30 minutes in Caches) and, in its extensions, the live
lists (`TVModel+Live.swift`: favourites, recently watched, hidden and pinned categories with
the Mac's rules from `LiveRules`) and recordings (`TVModel+Recordings.swift`, the
`RecorderHost` of the shared `Recorder`).

tvOS keeps nothing for sure except UserDefaults (about 500 KB): favourites and history use the
Mac's keys, hidden and pinned categories are stored per account as `live.visibility.<account>`
and `live.pinned.<account>`. Recordings and their list live in `Caches/Recordings/<account>/`;
tvOS may purge them, and entries whose file is gone are dropped at launch. Recordings run only
while the app is open: the idle timer is off during one, leaving the app stops it and keeps what
was recorded, a schedule that passed while the app was closed shows as missed, and below 2 GB
free a recording does not start.

**Screens** (`FernsyTV/Screens/`, from the Claude Design file `AppleTV.dc.html`; colours and focus
styles in `FernsyTV/Design/TVTheme.swift`; the design is 1920×1080, the Apple TV's size in points):

| Screen | Design screen | Shows |
|---|---|---|
| `RootScreen` (`MainTabs`) | – | welcome without an account, else the tab bar; a tab shows only with its source |
| `SignInScreen` (`WelcomeScreen`, `IPTVSignInScreen`, `JellyfinSignInScreen`) | `login`, `login2` | account choice, IPTV form with "Try the Demo", Jellyfin form |
| `StartScreen` | `home` | newest item to continue over its backdrop, Continue Watching, Recently Added |
| `LibraryGridScreen` (in `StartScreen.swift`) | `filme` | IPTV films or series: category, sorting, posters |
| `FilmScreen`, `SeriesScreen` (`DetailScreens.swift`) | `film`, `serie` | pages for IPTV and Jellyfin items |
| `JellyfinScreen`, `SearchScreen` (`JellyfinSearchScreens.swift`) | `jellyfin`, `suche` | Jellyfin views; search with letter row and system field |
| `VODPlayerScreen` | – | films, episodes, Jellyfin items; next-episode countdown |
| `ChannelListScreen` | `live` | category column, channel rows, pane with preview and now/next, long-press menu |
| `AllCategoriesScreen` | `kategorien` | category tiles with country chips, search, pin and hide |
| `GuideScreen` | `guide` | three hours per source on a time axis, play or record |
| `PlayerScreen` | `player`, `zap` | overlay with tabs and timeline, channel strip |
| `RecordingsScreen` (and `RecordingPlayerScreen`) | `aufnahmen` | running, scheduled, recorded; playback with resume |
| `SettingsScreen` | `einstellungen` | account, add account, playback languages, padding, log, version |

Films, series and Jellyfin come from the shared code (`ResumeStore` and `LibraryRules`,
`JellyfinStore`, `JellyfinPlayback`, `SearchIndex`); `TVModel+Library.swift` merges Start's rows.
Posters and backdrops load through `FernsyTV/Support/ImagePipeline.swift` (downsampled, memory
and `Caches/Images`). The Jellyfin library cache is in Caches (`JellyfinStore.cacheBase`), the
device id in UserDefaults (each Apple TV is its own device on the server). Headers above a scroll
view are focus sections, otherwise Up from the content skips them and reaches the tab bar.

The picture comes from `FernsyTV/Player/TVVideoSurface.swift`, which hosts the engine's display
layer; Live TV's preview and the player share the engine and the connection, so clicking a
previewed row continues full screen. Remote in the player: a click or swipe shows the overlay,
Left/Right ±10 s, Down the channel strip, Up the tabs, a click with the overlay goes back to
live, Play/Pause pauses, Back closes.

UI test identifiers: `channel.<id>` on channel rows, `guide.<channel>.<start epoch>` on guide
cells (value `scheduled` when planned), `strip.<id>` in the channel strip, `recording.<uuid>` on
recording cards (value: the status), `player.state` (value `playing`, `paused`, `loading`),
`player.behind`, `live.preview`, `live.allCategories`, `category.<id>`, `settings.*`,
`signin.*`, `welcome.iptv`.

**Run it.** `scripts/tv-run.sh` builds at background priority, boots the "Apple TV 4K (3rd
generation)" simulator (tvOS 27 runtime: `xcodebuild -downloadPlatform tvOS`), shows it
(Xcode 27.1 shows booted simulators in its own window), installs and launches Fernsy Dev with the
demo account. `KEY=value` arguments go into the app's environment and replace the defaults;
`--no-build` skips the build, `--log <file>` sets the log (default `build/tv-run.log`, emptied
per run):

```sh
scripts/tv-run.sh --log build/devtest/tv.log IPTV_AUTOPLAY=live:101
xcrun simctl io <device> screenshot shot.png    # screenshot of the simulator only
```

Debug builds behave like the Mac dev build: `IPTV_SERVER`, `IPTV_USER`, `IPTV_PASS` sign in
without the keychain (`FERNSY_NO_KEYCHAIN=1` keeps it out entirely); they start muted
(`IPTV_SOUND=1` for sound); streams only from the demo worker, `127.0.0.1` or `localhost` unless
`IPTV_ALLOWREAL=1`; `IPTV_AUTOPLAY=live:<id>` plays a channel once the catalog is loaded. An
empty `IPTV_SERVER=` starts without an account (welcome screen). Apple TV only:
`IPTV_MAXCONN=<n>` sets the stream limit (single-stream tests), `IPTV_TESTRECORD=<channel>:<starts
in s>:<seconds>[:<before min>:<after min>],…` plans recordings as on the Mac,
`IPTV_FRESHRECORDINGS=1` starts without earlier recordings, `IPTV_FRESHIMAGES=1` without cached
images, `IPTV_TESTRESUME=<key>:<position s>:<duration s>,…` and `IPTV_TESTHIDE=category:<id>,channel:<id>`
work as on the Mac (in memory), `JF_SERVER`/`JF_USER`/`JF_PASS` and `JF_CACHEONLY` as on the Mac, `JF_TESTMANY=<n>` repeats the
Jellyfin films, series and Recently Added up to n each (in memory, placeholder art) to fill grids,
`IPTV_TESTNOSPACE=1` refuses
recordings as if space were short, `IPTV_TESTBIGCATALOG=<n>` repeats the films and series with new
ids up to n each (a provider-sized catalog from the demo server), `IPTV_FRAMESTATS=1` logs late
frames once per second while any are late ("frames: 7 late of 60"), `IPTV_PLAYERMODE=info|strip` opens the player with that
overlay (screenshots without a remote), `IPTV_KEEPLIVE=1` keeps Live TV's source and view
(List/Guide) across launches in keychain-less runs (otherwise they stay in memory). The
player's test switches (`IPTV_TESTNET`, `IPTV_TRICKLEMORE`, `IPTV_TRICKLEKBIT`,
`IPTV_TESTSTALL`, `IPTV_TESTNODATA`, `IPTV_TESTNOVIDEO`, `IPTV_TESTSLOWSTART`,
`IPTV_TESTNOCONTINUE`, `IPTV_TESTCLOCK`, `IPTV_TESTJUMP`, `IPTV_LIVELEAD`, `IPTV_AUDIOLEVEL`) are
read in `FernsyPlayer` and work the same on both platforms.

**Debug MCP.** With `IPTV_MCP=1` and `IPTV_MCPTOKEN=<token>` (tv-run sets the token `test`) a
debug build listens on `http://127.0.0.1:52325/mcp` (the simulator shares the Mac's network):
`play`, `stop_playback`, `seek`, `now_playing` (also the preview), `playback_diagnostics`,
`snapshot`, `get_log`, `record`, `list_recordings`, `cancel_recording`, `play_item` (films
`movie:<id>`, IPTV episodes `episode:<series id>:<episode id>`, Jellyfin `jellyfin:<id>`)
(`FernsyTV/Debug/TVTools.swift`). Release builds have no listener.

**UI tests.** `scripts/tv-uitest.sh` builds the app and "Fernsy TV UITests" and runs them on the
simulator (about 12 minutes for all): sign-in, tab bar, Live TV (preview, single stream, hiding,
pinning), guide, player and strip, recordings, settings, Start, grids, film and series pages,
Jellyfin, search. Tests that need the local test Jellyfin skip without it (CI has none): start it
with `scripts/jellyfin-test-server.sh` (Docker; container `fernsy-jf-fixtures` on 127.0.0.1:8097,
user `fixture`, an 8-minute film resuming at 2:30 and three 2-minute episodes, the first two
watched) and remove it afterwards with
`docker rm -f fernsy-jf-fixtures`. Jellyfin keeps no resume position for items under 5 minutes and
the demo films are under a minute, so resume tests use the fixture film or `IPTV_TESTRESUME`. Further arguments go to `xcodebuild`, e.g.
`scripts/tv-uitest.sh "-only-testing:Fernsy TV UITests/PlayerUITests"`. `--shard 2/3` runs only one
of three parts (every test class in exactly one, balanced by test count, found in the sources) and
`--list 3` prints the parts; CI runs the three parts on three runners in parallel. Another
simulator: `DEVICE_NAME="…" scripts/tv-uitest.sh`. Tests derive from
`FernsyUITestCase` (`UITestSupport.swift`): the demo account with the debug MCP, and on a
failure the app's log as an attachment. Tests wait for a state, not a fixed time:
`waitForFocus`, `waitForPlayerFocus` (the value of the player surface `player.surface`), `waitForLog`,
`pressAndWaitForFocusMove` and `typeOnKeyboard`; `showTab` waits for the `tabs` element's value
(the selected tab). A sleep that stays says why in a comment ("real time" for checks that
nothing happens, or no state to wait for). The script passes `-collect-test-diagnostics never`;
without it a failing test makes `xcodebuild` run `simctl diagnose` for many minutes, which looks
like a hang. At the end of each test Xcode quits the app, so the simulator shows the home screen.
Pitfalls found while writing them: a press right after a screen appears can go nowhere until it
has taken focus (wait for its focus, e.g. `waitForPlayerFocus`); `try? await Task.sleep` in a `.task(id:)` returns at once when
the task is cancelled, so code after it runs (check the result); tvOS lists context-menu entries
as cells named by their symbol.

**What the simulator cannot show.** VideoToolbox hardware decoding fails there (the log says
`hwaccel initialisation returned error`) and FFmpeg decodes in software, with occasional
artefacts; check picture and performance on a real Apple TV. Right after a relaunch the demo
server may close connections for about 20 s.

### iPhone and iPad

The target "Fernsy iOS" (`FernsyiOS/`, product `FernsyiOS.app`, one app for iPhone and iPad,
iOS 27, same bundle id as the Mac and Apple TV apps: universal purchase) shares the Apple TV
app's model and helpers: the `FernsyTV` folder is a member of the iOS target, except the files
listed in its exception set in `Fernsy.xcodeproj` (`FernsyTVApp.swift`, `Screens/`,
`Design/TVTextEntry.swift`, the asset catalog, `InfoPlist.xcstrings`). **A new file in
`FernsyTV/Screens/` must be added to that list** (Xcode does not take folders there), or the
iOS build compiles a tvOS screen and fails. Shared files use `#if os(tvOS)` for tvOS-only API.
The screens in `FernsyiOS/` are drawn for touch and read only `TVModel`; there are no
recordings on iOS (ios-app).

- `scripts/ios-run.sh [--no-build] [--log <file>] [KEY=value …]` builds at background priority,
  boots the "iPhone 18 Pro" simulator with its window (`DEVICE_NAME="iPad Pro 13-inch (M5)"`
  for an iPad) and launches Fernsy Dev with the demo account. The Apple TV's debug switches
  (`IPTV_AUTOPLAY=live:<id>`, `IPTV_MCP=1` with token `IPTV_MCPTOKEN`, `IPTV_SOUND=1`, …) work
  the same; the debug MCP server listens on port 52326 (Apple TV: 52325).
- Screenshots: `xcrun simctl io <device> screenshot <file>`. The simulator takes no touch input
  from scripts, so debug switches open screens: `IPTV_TAB=start|live|films|series|jellyfin|search|settings`,
  `IPTV_LIVEVIEW=list|guide`, `IPTV_ALLCATEGORIES=1`, `IPTV_DETAIL=movie:<id>|series:<id>` (from the
  Movies or Series tab), `IPTV_SEARCH=<query>`, `IPTV_PLAYERMODE=channels` (the player's channel
  list), `IPTV_KEEPCONTROLS=1` (the player's controls stay).
- `scripts/ios-uitest.sh [--no-build] [xcodebuild arguments]` runs the UI tests
  (`FernsyiOSUITests`, target "Fernsy iOS UITests") with real touch input on the iPhone
  simulator, `DEVICE_NAME="iPad Pro 13-inch (M5)"` on the iPad one. On iPhone the player turns
  the interface to landscape by itself; the tests turn the test device to `landscapeLeft`
  (interface landscape right) and draw gestures on the window, or taps and swipes land at
  portrait coordinates.
- CI (`tests.yml`, job `ios`) builds the target for the iOS simulator; a shared file that
  breaks it fails the run. The UI tests run locally only for now (CI would have to download the
  iOS runtime as it does the tvOS one).
- The icons come from the Mac icon: `swift scripts/make-ios-icons.swift`.
- Picture in Picture and AirPlay need a real device; the simulator checks screens and flows.

### Tests and FernsyCore

Fernsy's platform-independent logic lives in the local package `Packages/FernsyCore` (macOS and
tvOS), linked by both app targets: Xtream models, client and EPG store, channel names, Jellyfin
models and JSON decoder, the recording plan and gap tracker, the slow-delivery rule
(`DeliveryMonitor`, used by `HTTPByteSource`), content history, track choice, media info and the
app log, the keychain wrapper (`CredentialStore`) and the MCP HTTP server and JSON-RPC
dispatcher. FFmpeg code is in `Packages/FernsyPlayer` (see Build), so these tests never need
FFmpeg; code that needs AppKit or SwiftUI views stays in the app. Public
API is `public`; package strings use `String(localized: …, bundle: .module)` and live in the
package's own `Resources/Localizable.xcstrings`.

`scripts/test.sh` runs the tests (Swift Testing) on macOS and builds the package for the tvOS
simulator; `scripts/test.sh --tvos-sim` also runs them on a tvOS simulator, which needs the tvOS
runtime (`xcodebuild -downloadPlatform tvOS`, several GB). The tests need no network and no
account: network answers come from `Tests/FernsyCoreTests/Fixtures` – Xtream answers recorded
once from the demo server (public demo account, lists cut to five entries), Jellyfin answers
recorded from a throwaway local Docker Jellyfin (two generated clips; ids, tokens, addresses and
online metadata replaced). Never record fixtures from a real provider or the user's Jellyfin.
`XtreamStub` answers every request of the tests, so nothing leaves the machine.

CI (`.github/workflows/tests.yml`) runs the same on pushes to `main` and on pull requests, but
not for pushes that change only `openspec/**` and Markdown files, and not on change branches
(they are tested locally in full before they are pushed and merged). `release.yml` first looks
for a passing run of its commit (job `reuse`: waits for one still running) and builds right
away if there is one; otherwise it calls `tests.yml` itself, so a nightly or release is never
built from a commit whose tests fail. A nightly started right after a merge therefore waits for
the merge's run instead of testing the same commit a second time.

### UI texts and translations

The UI's source language is English (US spelling): literals in the code (`Text("…")`,
`Button("…")`, `String(localized: "…")`, App Intents titles and Siri phrases) are English, and
the catalogs `Fernsy/Localizable.xcstrings`, `Fernsy/AppShortcuts.xcstrings` and
`Fernsy/InfoPlist.xcstrings` hold the German translation of every key. A language Fernsy does
not have falls back to English. A new string needs its German translation in the catalog
(Xcode adds the key on the next build). A new language is added in the project's
Localizations (Xcode then shows a column for it in every catalog); only translations are
needed, no code. Wording of the German UI did not change when the source flipped from German
to English (change `fernsy-core-package`).

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
