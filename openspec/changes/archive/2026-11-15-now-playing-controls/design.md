# Design

## Context

Fernsy decodes with FFmpeg and plays through `AVSampleBufferDisplayLayer`,
`AVSampleBufferAudioRenderer` and a render synchronizer (`PlayerEngine`), not through
`AVPlayer`. AVPlayer-based apps get some of the system integration for free; Fernsy gets none:
there is no `MPNowPlayingInfoCenter` or `MPRemoteCommandCenter` code in the repo. AirPods ear
detection, AirPods controls, the Lock Screen, Control Center, the Apple TV's Control Center and
the iPhone remote, and the Mac's media keys all reach the app through those remote commands, so
none of them reach Fernsy today.

The pieces this builds on:
- `PlayerEngine.setPaused(_:)`, `seek(to:)` and `seek(by:)`, used by the player's own controls.
  Pausing live TV there already continues time-shifted.
- `AudioOutput` sets the audio session to playback / movie playback on iPhone, iPad and Apple TV
  and activates it before a playback (`prepare()`).
- The Mac has one player window; `AppModel.nowPlaying` (`PlayItem`: title, subtitle, kind) says
  what it plays. iPhone, iPad and Apple TV share `TVModel`, which has one engine and knows the
  playing channel, recording or on-demand item (`playing`, `playingRecording`, `playingVOD`; the
  assistant's `now_playing` already turns them into a title and second line).

## Goals / Non-Goals

**Goals:**
- One implementation in the FernsyPlayer package for all three apps.
- A system pause behaves exactly like the player's pause button.

**Non-Goals:**
- Pausing on a lost audio route (see proposal; follow-up if ear detection is not enough).
- Timeshift as a seekable range in Now Playing: live TV shows as live even while time-shifted.

## Decisions

### 1. One Now Playing controller in FernsyPlayer, fed by the app

A `NowPlaying` controller in `Packages/FernsyPlayer` owns the command handlers and the info
dictionary. It observes one `PlayerEngine` (status, `isPaused`, `isLive`, progress) and gets the
item's text from the app (`title`, `subtitle`) when the app starts showing an item, `nil` when the
player closes. The engine itself does not know titles, so it cannot do this alone.

Rejected: separate code in each app (three copies of the command mapping, and the rules for live
and on-demand would drift); putting titles into `PlayerEngine` (it plays URLs and files and should
stay free of catalog types).

### 2. Commands go through the engine's public controls

play → `setPaused(false)`, pause → `setPaused(true)`, play/pause → `togglePause()`, skip →
`seek(by: ±interval)`, position → `seek(to:)`. The same path as the buttons keeps live pause
time-shifted, the Jellyfin restart for non-seekable transcodes, and the `ended` → play from start
rule. Play and pause are explicit (idempotent), so a duplicated command cannot flip the state
twice; only play/pause toggles.

Rejected: setting the synchronizer's rate directly (bypasses the session, timeshift and Jellyfin
handling).

### 3. Which commands are on

All commands are registered once; `isEnabled` follows the item: play, pause and play/pause for
every item; skip back/forward (15 s, the system's usual interval) and position only for on-demand
items (not live). When the app hands over `nil`, the info is cleared (`nowPlayingInfo = nil`),
`playbackState` goes to `.stopped` and all commands are disabled, so media keys and AirPods go back
to other apps.

Rejected: removing and re-adding targets per item (more churn for the same effect).

### 4. Info updates on change, not per frame

The info carries title, artist line (subtitle), `isLiveStream`, and for on-demand
`playbackDuration`, `elapsedPlaybackTime` and `playbackRate`. It is written when the item, the
paused state, the status (buffering counts as rate 0) or a seek changes; the system extrapolates
the elapsed time in between. On the Mac `playbackState` is set explicitly (`.playing`/`.paused`),
because macOS picks the Now Playing app by it; iOS and tvOS pick it from the active audio session,
which `AudioOutput.prepare()` already activates.

Rejected: writing the info with every progress tick (several times a second, needless work and
log noise).

### 5. Apple TV: the Siri Remote stays with the player screens

In the Apple TV player the Siri Remote's play/pause reaches the focused view
(`onPlayPauseCommand`) as today. Remote commands come from Control Center, the iPhone remote and
AirPods. Because play and pause are explicit (decision 2), a press that arrived both ways would
still not flip twice except for the toggle command; a UI test checks one press toggles once.

### 6. What is handed over

Mac: the `PlayItem` of the player window. iPhone, iPad, Apple TV: the full-screen player's
channel, recording or on-demand item, with the same title and second line as the assistant's
`now_playing`. The Apple TV channel list's preview is not handed over (it is not "playing" for the
user; its sound is off by default).

## Risks / Trade-offs

- [Ear detection may need more than Now Playing on some devices] → the real check with AirPods on
  the user's iPhone and Mac (task 4.1) decides whether the route-change follow-up is needed.
- [Fernsy takes Now Playing from Music or a podcast app while it plays] → expected system
  behaviour; it is released when the player closes.
- [Simulators and CI cannot send real remote commands] → the command mapping is tested through
  the controller's handler function with a stand-in player; real commands are checked on the Mac
  with a posted media key and on devices by hand.

## Notes from implementing

- The Now Playing log line is written once the new item has started (`playing` or `paused`):
  when the app hands over the item, the engine may still be on the previous one.
- iPhone simulator: mediaremoted lists Fernsy Dev with the channel as Now Playing at rate 1, so
  the active audio session is enough there; no extra session option was needed.
- `testPlayPauseTogglesOnce` first failed in the parallel run because it pressed before the
  player had focus (the press went nowhere); it waits for the player's focus like the other
  tests now.
- Task 3.3: the first iPhone run in the VM failed almost everywhere because "IPTV only with VPN"
  was still on in the VM simulator's app defaults from an earlier run (the VM has no VPN, so the
  demo server was refused). Uninstalling the app there fixed it; the playback tests then ran on
  the host (11 passed, 1 skipped). All Apple TV UI tests pass on the host.
- Task 2.2: the play/pause media key, posted as a system-defined event (`NX_KEYTYPE_PLAY`) while
  Fernsy Dev played channel 101 from the demo server, arrived as `togglePlayPause`: the player
  paused (debug MCP `now_playing`: paused) and the second press resumed it.
- Task 4.1, Mac (2026-11-14): with a Release build of this branch in /Applications, the user
  confirmed that taking the AirPods out pauses Fernsy and putting them back resumes it ("klappt").
  Ear detection through Now Playing covers the case that started this change on the Mac.
- The check with real AirPods on the iPhone was not done: the user closed the change after the Mac
  check. On iPhone, iPad and Apple TV the behavior is covered by the simulator (mediaremoted lists
  Fernsy as Now Playing) and the unit tests, not by real AirPods. The route-change pause stays out.
