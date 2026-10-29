# Tasks

## 1. Automatic Picture in Picture only while playing

- [x] 1.1 In `FernsyiOS/PictureInPicture.swift` `attach`, subscribe to `engine.$status` and set `canStartPictureInPictureAutomaticallyFromInline` true for loading, playing, paused, buffering and false for idle, ended, failed; log the switch under `.pip`. Remove the fixed `= true`.
- [x] 1.2 Make `pictureInPictureControllerIsPlaybackPaused` report `true` for an idle, ended or failed engine.
- [x] 1.3 Update the type's doc comment to say automatic start follows playback.
- [x] 1.4 Returning from Picture in Picture keeps playing (design 3): ignore `setPlaying(false)` while restoring, continue playback after `didStop` if it played when "back" was tapped; log both under `.pip`.

## 2. Verify

- [x] 2.1 Build the iOS app for the simulator (`Fernsy iOS`, Debug) and run the iPhone UI tests (`FernsyiOSUITests`, demo server via `IPTV_SERVER` demo as in the tests); all pass.
- [x] 2.2 On the real iPad (Release build per the ipad-release recipe, signed in to the demo server `https://fernsy-demo.mobilistics.workers.dev`, demo/demo): play a demo channel, leave the app — PiP opens with sound; return — the player continues playing; close the player, leave the app — no window. Repeat with an on-demand item. Needs the user to press the home gesture; the app log (`.pip` lines) confirms the switches. Done 2026-10-29 by the user on the iPad (live channel and Jellyfin films); the log showed "automatic Picture in Picture off" after every close and no window; on the second run iOS did not pause on return, so design 3's guard did not have to act.
- [x] 2.3 `openspec validate --all --strict` passes.
