# Proposal

## Why

Taking AirPods out of the ear does not pause Fernsy. With automatic ear detection the system sends
"pause" to the app shown as Now Playing, but Fernsy never registers as one: it plays through its
own renderers, not AVPlayer, and has no Now Playing information or remote command handlers on any
device. The same gap means AirPods controls, the Lock Screen, Control Center and the Mac's media
keys do nothing for Fernsy.

## What Changes

- While something plays, Fernsy publishes Now Playing information (title, channel or series line,
  live or position and duration, playing or paused) on Mac, iPhone, iPad and Apple TV, and clears
  it when playback stops.
- Fernsy answers the system's play, pause and play/pause commands for every source, so AirPods ear
  detection, AirPods controls, the Lock Screen, Control Center and media keys pause and resume it.
  Pausing live TV continues time-shifted, as the player's own pause button does.
- For on-demand media (films, episodes, recordings, Jellyfin, Fernsy Cloud, archive) the system's
  skip back/forward and the position slider work; live TV offers only play/pause.

Out of scope:
- Reacting to an audio output that disappears (route change "old device unavailable", the Mac's
  default output device changing). This change checks first whether ear detection through Now
  Playing already covers the user's case; the route-change pause is a possible follow-up change.
- A setting to switch the behavior off (none is needed while the system's own controls decide).
- Artwork (channel logos, posters) in Now Playing.
- Next/previous track commands (channel zapping, next episode).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playback`: adds a requirement "System media controls" (Now Playing information and the
  system's play/pause and seek commands, on every device).

## Impact

- `Packages/FernsyPlayer`: a new Now Playing controller next to `PlayerEngine` (MediaPlayer
  framework: `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`), shared by all three apps.
- Mac: `Fernsy/Views/PlayerScreen.swift` hands over the `PlayItem`'s title and subtitle.
- iPhone, iPad, Apple TV: `FernsyTV/Model/TVModel.swift` (shared with the iOS app) hands over the
  playing channel, recording or on-demand item.
- No new entitlement or background mode; no App Review note needed.
