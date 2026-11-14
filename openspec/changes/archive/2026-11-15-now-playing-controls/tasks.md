# Tasks

## 1. Now Playing controller (FernsyPlayer)

- [x] 1.1 Add `NowPlaying` to `Packages/FernsyPlayer/Sources/FernsyPlayer` (design 1–4): `attach(engine:)`, `show(title:subtitle:)` / `clear()`, command handlers mapped to `setPaused`, `togglePause`, `seek(by:)`, `seek(to:)` through a small player protocol the engine conforms to, commands enabled per item (live: play/pause only), info written on item, pause, status and seek changes, `playbackState` set on macOS, everything cleared and disabled on `clear()`. Log one info line per item ("now playing: <title>, live|on demand") and one per command received. Verify with `swift test --filter NowPlayingTests` in `Packages/FernsyPlayer`.
- [x] 1.2 Add `NowPlayingTests` with a stand-in player: pause/play/toggle/skip/position commands call the right methods; play and pause are idempotent; a live item has `isLiveStream`, no duration and skip/position disabled; an on-demand item has duration, elapsed time and rate 0 while paused or buffering; `clear()` empties the info and disables every command. Verify the full package suite passes (`swift test` in `Packages/FernsyPlayer`), and that the play/pause test fails with the handler's call removed.

## 2. Mac

- [x] 2.1 Wire `NowPlaying` in `Fernsy/Views/PlayerScreen.swift`: attach the window's engine, `show` the `PlayItem`'s title and subtitle when an item loads, `clear()` when the window closes or playback stops. Verify on the demo server with Fernsy Dev (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev IPTV_USER=demo IPTV_PASS=demo IPTV_AUTOPLAY=live:101`, then `IPTV_AUTOPLAY=episode:<series>:1`) that the log shows the "now playing" line with live / on demand, and that closing the player logs the clear.
- [x] 2.2 Real command on the Mac: with Fernsy Dev playing channel 101 from the demo server as in 2.1, post the play/pause media key (a small Swift script in the scratchpad posting an `NSEvent.otherEvent` system-defined `NX_KEYTYPE_PLAY` down/up) and verify the log shows the command and the player pauses, then resumes on a second press. Ask the user first, since the key goes to whatever app is Now Playing; if posting the key is not allowed, record that and leave it to 4.1.

## 3. iPhone, iPad and Apple TV

- [x] 3.1 Wire `NowPlaying` in `FernsyTV/Model/TVModel.swift` (shared with the iOS app): attach `engine` once, `show` the playing channel, recording or on-demand item with the title and second line the assistant's `now_playing` uses, `clear()` when the player closes; not for the channel list preview (design 6). Verify the iOS and tvOS apps build, and on the demo server (`IPTV_AUTOPLAY=live:101` in the iPhone simulator) that the log shows "now playing: …, live".
- [x] 3.2 Apple TV remote unchanged: add `testPlayPauseTogglesOnce` to `FernsyTVUITests/PlayerUITests` (demo server, channel 101): one `XCUIRemote.shared.press(.playPause)` pauses (the player's state reads paused), a second resumes. Verify with `scripts/tv-uitest.sh "-only-testing:FernsyTVUITests/PlayerUITests"` on the host, and that the existing `PlayerUITests` still pass.
- [x] 3.3 Run the iPhone UI tests in the VM (`scripts/vm.sh scripts/ios-uitest.sh`, playback tests on the host) and the Apple TV UI tests on the host. Verify all pass, apart from failures that also fail on `main`, which are named in design.md.

## 4. Real devices

- [x] 4.1 The user's check with AirPods (needs real AirPods with ear detection): on the Mac (Release build from this branch, after asking), play a film and a live channel, take the AirPods out → Fernsy pauses; put them back → it resumes. Record the result under "Notes from implementing" in design.md, including whether the route-change pause (proposal, out of scope) is still wanted. The iPhone part was left out at the user's decision (see design.md).

## Workflow follow-up

- Archive the change on `change/now-playing-controls` after the checks, then merge into `main` and push when the user agrees.
- The user-visible commit carries `Release-Note-de` / `Release-Note-en` trailers (AirPods, Lock Screen, Control Center and media keys pause and resume Fernsy).
