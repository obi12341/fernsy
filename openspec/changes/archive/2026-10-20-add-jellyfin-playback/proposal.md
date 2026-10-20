# Proposal

## Why

The Jellyfin browser (change `add-jellyfin-library-browser`) shows films and series but cannot
play them yet. The playback analysis (archived `analyze-jellyfin-playback`) showed that Fernsy's
player plays nearly the whole library directly; the gaps are bitmap subtitles (34 % of the
user's videos have some, 16 % only bitmap ones), Dolby Vision profile 5 and, on M1/M2, AV1.
The user wants playback with a fallback to Jellyfin transcoding when Fernsy cannot play an item
itself.

## What Changes

- Play Jellyfin films and episodes in Fernsy's player: Direct Play from the original file by
  default; when the item cannot be played locally (Dolby Vision profile 5, a codec this Mac
  cannot decode, or a failure while opening), Fernsy falls back to a transcode by Jellyfin.
- Resume from the position stored on the server, report playback start, progress and stop to
  Jellyfin (so watched state, resume and "Next Up" follow everywhere).
- Audio and subtitle tracks, including Jellyfin's external subtitle files.
- **Bitmap subtitles (PGS, VobSub, DVB) are rendered by the player** (user decision) – for
  Jellyfin and for IPTV channels with DVB subtitles. Several text subtitles at once are shown
  together (they were reduced to the newest one).
- After an episode, offer the next one with a countdown (user decision).
- Play buttons in the Jellyfin views become active; the "playback follows later" hint goes.

Out of scope: 7.1 audio output (still down-mixed to 5.1), styled ASS rendering (libass), real
Dolby Vision processing, HLS playback, AV1 software decoding (dav1d), music, offline downloads,
casting/remote control by other Jellyfin clients, Jellyfin playlists.

## Capabilities

### New Capabilities
- `jellyfin-playback`: playing Jellyfin films and episodes, direct play vs. transcode fallback,
  resume and progress reporting, next episode.

### Modified Capabilities
- `playback`: "Audio and subtitle tracks" now includes bitmap subtitles and simultaneous text cues.
- `jellyfin-library`: "Playback is announced but not available yet" is removed (Play works).

## Impact

- Player: `PlaybackSession` (bitmap subtitle decoding, external subtitle cues, start offset for
  transcodes), `PlayerEngine` (seeking a transcode = restart at a position), `PlayerScreen`
  (bitmap subtitle overlay, next-episode countdown, Jellyfin items), `FFShim` (bitmap subtitle
  decoding to RGBA).
- Jellyfin: `JellyfinClient` (PlaybackInfo with a device profile, progress endpoints, active
  encodings, subtitle files), `JellyfinStore`, Jellyfin views (Play buttons), `AppModel`/
  `PlayItem` (Jellyfin item kind).
- Writes to the user's server: playback progress and played state of test items (backed up and
  restored after tests).
