# Tasks

## 1. Own identity

- [x] 1.1 Debug configurations of `Fernsy` and `Fernsy Direct`: `PRODUCT_BUNDLE_IDENTIFIER = de.mobilistics.fernsy.dev`, `INFOPLIST_KEY_CFBundleDisplayName = "Fernsy Dev"`, `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon-Dev`. Verify: `plutil -p build/dd/Build/Products/Debug/Fernsy.app/Contents/Info.plist` shows the dev id and name; a Release build (`build/ddr`, `CODE_SIGNING_ALLOWED=NO`) still shows `de.mobilistics.fernsy` and "Fernsy".
- [x] 1.2 `scripts/make-dev-icon.swift` creates `AppIcon-Dev.appiconset` from `AppIcon` with an orange "DEV" band. Verify: the icon in the built dev app (`sips`/Quick Look of the `.icns`) shows the band at every size.
- [x] 1.3 In DEBUG, `Keychain.service` is `de.mobilistics.fernsy.dev` and `Recorder`'s folder is `~/Movies/Fernsy Dev`. Verify: a demo run with `IPTV_TESTRECORD=<ch>:5:30:0:0` writes into `~/Movies/Fernsy Dev`, and `security find-generic-password -s de.mobilistics.fernsy.dev` finds nothing after a run with `FERNSY_NO_KEYCHAIN=1`.
- [x] 1.4 First launch without any environment while the installed app runs: the dev build shows the sign-in screen and a new container `~/Library/Containers/de.mobilistics.fernsy.dev` appears; `defaults read` of the installed app's domain is byte-identical before and after (compare exports). Only with the user's consent if a recording is running in the installed app.

## 2. Quiet by default

- [x] 2.1 `PlayerEngine`: DEBUG starts muted unless `IPTV_SOUND=1` and does not write `player.volume`. Verify: demo run, MCP `playback_diagnostics` on port 52324 shows playing, the player's mute state is on (MCP `now_playing` or log), the dev defaults have no `player.volume` after changing it.
- [x] 2.2 `AppActivation.bringToFront()` replaces the `NSApp.activate()` calls in `MenuBar.swift`, `Recorder.swift`, `MCPTools.swift`, `PlayerScreen.swift` and the `PlayerWindow` front repeats; in DEBUG without `IPTV_ACTIVATE=1` it neither activates nor orders in front of other apps. Verify: during a demo run with MCP `play`, `$S/order` shows the frontmost app unchanged, and a window screenshot by window id of the player still works.

## 3. Demo-server guard and copied data

- [x] 3.1 Stream guard in DEBUG for live tuner, films, episodes and recordings: hosts other than the demo worker, `127.0.0.1` and `localhost` are refused unless `IPTV_ALLOWREAL=1`, with the error card text "Debug-Build: echte Anbieter nur mit IPTV_ALLOWREAL=1" (de + en) and an error log entry. Verify: a run with `IPTV_SERVER=https://example.invalid` and `IPTV_AUTOPLAY` shows the card and no request to `/live/` (log); the demo run plays as before.
- [x] 3.2 `IPTV_COPIEDACCOUNT=<folder>` opens a copied account folder offline: cached catalog, EPG and recordings list, no API calls, streams refused. Verify: with a copy of the demo account folder (from the dev container itself), the library shows its channels with the network blocked for that host (log shows no catalog request).
- [x] 3.3 `scripts/dev-copy-prod.sh` (`--list`, `--account <n>`, `--settings`) per design E. Verify: run it for the user's account, compare checksums of the installed app's container before and after (unchanged), the copy's `recordings.json` has no `scheduled`/`recording` entry, the dev defaults hold none of the excluded keys, and the dev build with `IPTV_COPIEDACCOUNT` shows the channels and recordings list without playing anything.

## 4. Scripts and docs

- [x] 4.1 `scripts/dev-run.sh` per design F. Verify: `scripts/dev-run.sh --log $S/dev.log IPTV_AUTOPLAY=1` builds with `taskpolicy -b` (visible in `ps -o pri`), starts the dev build against the demo server, and prints whether the installed app runs.
- [x] 4.2 DEVELOPMENT.md: section "Dev build next to the installed app" (identity, quiet defaults, `IPTV_SOUND`, `IPTV_ACTIVATE`, `IPTV_ALLOWREAL`, `IPTV_COPIEDACCOUNT`, both scripts, dev container path). Verify: the section exists and names every switch.
- [x] 4.3 `openspec validate --all --strict` exits 0; Debug, Direct and Release builds have 0 warnings.

## Workflow follow-up

- Internal change, no Release-Note trailers (debug builds only).
- After the merge, update the local helpers in the session scratchpad (`jfrun.sh`, backup paths) to the dev container, and the memory notes that name the shared container.
- Offer, separately and only with consent, to remove old debug leftovers from the installed app's container (test account folders, `jellyfin.deviceId.debug`).
