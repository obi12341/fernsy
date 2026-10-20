# Proposal

## Why

Live TV could only be watched as it came: pausing just stopped the picture, missed moments
were gone, and nothing could be kept for later. Users asked to rewind live TV and to schedule
recordings from the program guide (October 2026, after the 1.0 submission).

## What Changes

- Live channels are received into an on-disk timeshift buffer and played from there:
  pause, rewind, seek and "back to live" work on live TV.
- Recordings: schedule shows from the guide or channel list, record the current show from
  the player (from its start, as far as the buffer reaches), stored as `.ts` files in
  `~/Movies/Fernsy`, listed and playable in a new "Recordings" section.
- Watching and recording one channel share one connection; when the account has no free
  connection the app asks before taking it (user decision: "ask").
- Fernsy stays in the menu bar when all windows are closed, so recordings keep running
  (user decision: recordings only while the app runs, no background helper).
- FFmpeg build gains the MPEG-TS muxer (still LGPL, no encoders); new sandbox entitlement
  for the Movies folder.

Out of scope: recording while the app is not running, waking the Mac from sleep, provider
catch-up/archive streams, series recordings ("record every episode"), editing/cutting
recordings, exporting to other formats.

## Capabilities

### New Capabilities
- `timeshift`: pausing and rewinding live TV from a local buffer, live-edge behavior.
- `recordings`: scheduling, running, storing, listing and playing recordings, connection conflicts.
- `menu-bar`: the menu bar item and running without windows.

### Modified Capabilities
- `playback`: closing the player no longer necessarily closes the stream (a recording may keep it).

## Impact

- Player architecture: live TV runs through a tuner (headless session) → MPEG-TS remux →
  on-disk buffer → player session; new files in `Fernsy/Player/` and `Fernsy/Recording/`.
- `scripts/build-ffmpeg.sh` (`--enable-muxer=mpegts`), `Config/Fernsy.entitlements`
  (`com.apple.security.assets.movies.read-write`), Settings, guide, channel list, player UI.
- Disk use: roughly 2–4 GB per hour of buffer for HD channels.
- Store texts and README updated for version 1.1.
