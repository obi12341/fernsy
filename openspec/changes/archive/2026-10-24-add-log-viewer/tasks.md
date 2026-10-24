# Tasks

## 1. Log store

- [x] 1.1 `Fernsy/App/AppLog.swift`: entry, levels, categories, thread-safe ring (20,000), batched file append to `Caches/Fernsy/logs/current.log`, rotation to `previous.log` at launch, 4 MB limit (keep the newest half), reading the previous run, clear. DEBUG mirror to stderr in the old `debugLog` format. Verify: build succeeds, and a debug run writes `current.log` while stderr output looks as before.
- [x] 1.2 Redaction (query `username/password/api_key/token`, Xtream path credentials, registered secrets ≥ 4 chars). Register the secrets from `AppModel` (Xtream password) and `JellyfinStore` (token) on sign-in and remove them on sign-out. Verify: a debug self-check `IPTV_LOGSELFTEST=1` logs sample URLs and asserts that no secret remains in the stored text.

## 2. Log calls

- [x] 2.1 Move the `debugLog` calls in Player (PlaybackSession, PlayerEngine, HTTPByteSource, LiveTuner, TimeshiftWriter, TSAudioTap, DVDecoder, PictureInPicture, TrackChooser) to `AppLog` with a category and level following design §3. `[test]` messages stay on `debugLog`. Verify: `grep -rn 'debugLog(' Fernsy` only lists `[test]` hooks and the definition.
- [x] 2.2 Same for Recorder, JellyfinStore, JellyfinPlayback, AppModel, EPGStore, FernsyApp, PlayerScreen, LibraryView and SearchResultsView. Verify with the same grep.
- [x] 2.3 Add the missing events: playback start and end with the item (channel, film, episode, Jellyfin item), playback errors shown to the user (error), catalog or sign-in failure (error), recording failed (error, with reason). Verify in the run of 4.2.

## 3. Log window

- [x] 3.1 `Fernsy/Views/LogView.swift` with `LogModel` (pulls at most 4×/s): a Table with time, level, category and message, plus the level picker, category menu, search and current/previous picker. Follows new entries at the bottom. Verify: the window shows live entries during a demo run.
- [x] 3.2 Copy (selection or all filtered), Save … (`NSSavePanel`, plain text), Clear. Add the entitlement `com.apple.security.files.user-selected.read-write`. Verify: a saved file contains the filtered entries in the line format.
- [x] 3.3 `FernsyApp`: `Window("Protokoll", id: "log")` and the Window menu command "Protokoll" ⌥⌘L. Verify: the menu item opens the window, and a second use brings it to the front.

## 4. Localization, docs, verification

- [x] 4.1 UI strings in `Localizable.xcstrings` (de + en) via `xcstringstool sync`, in the repo's JSON format, with no stale keys. README: the log, its file location and the review note for the new entitlement. Verify: build without missing translations.
- [x] 4.2 Demo server run (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, demo/demo, `FERNSY_NO_KEYCHAIN=1`) with `IPTV_AUTOPLAY=live:101`, `IPTV_TESTNET=drop:20` and `IPTV_TESTRECORD=102:10:40` with `IPTV_TESTNODATA=offline:600`. Expected log entries: playback started (info), network reconnect (warning), recording failed with "no data" (error). `grep -E 'demo/demo|password=demo'` on `current.log` finds nothing.
- [x] 4.3 Restart the debug app and confirm that the previous run is selectable in the window and that `previous.log` exists. Screenshot of the log window only (`screencapture -l <window id>`).
- [x] 4.4 Release build (`scripts/build-dmg.sh`) under the sandbox: the log file is written in the container, and Save … writes to a chosen folder (the user checks this by hand).
- [x] 4.5 `openspec validate --all --strict` passes.

## Workflow follow-up

- `/opsx:archive`, then commit, merge into main and push, only after the user agrees.
