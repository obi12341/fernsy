# Proposal

## Why

Fernsy decodes every audio track itself with FFmpeg and hands PCM to the system:
- at most 5.1, and 7.1 is mixed down to 5.1 (`ffs_output_channels`);
- Dolby Atmos is lost (the archived `analyze-jellyfin-playback` design records this).

Two more things make it worse on Apple TV:
- **No audio session.** The Apple TV app sets up no `AVAudioSession` at all, and the iPhone app
  only sets a category. Without the session asking for multichannel, the system usually plays 5.1
  as stereo. The user's main concern is surround on the Apple TV.
- **Atmos never reaches the receiver.** Dolby's application developer guide (Dec 2024) says tvOS
  and iOS decode Dolby Digital and Dolby Digital Plus, including Atmos (E-AC-3 with JOC), themselves
  when the app hands the bitstream to `AVSampleBufferAudioRenderer` with
  `AVSampleBufferRenderSynchronizer`; Fernsy uses both already. PCM an app decoded itself is never
  shown as Dolby Atmos.

## What Changes

- **Audio session (tvOS, iOS).** The session is set up for movie playback, activated, allowed
  multichannel content, and asks for as many channels as the current output supports
  (`supportedOutputChannelLayouts`, `maximumOutputNumberOfChannels`). It follows route changes.
- **PCM output follows the output.** Tracks Fernsy decodes itself are output as stereo, 5.1 or 7.1,
  depending on the source and what the output supports. 7.1 is no longer mixed down to 5.1 when the
  output can play it. Every PCM buffer carries a channel layout that matches FFmpeg's channel order.
- **Dolby bitstream to the system.** AC-3 and E-AC-3 tracks are no longer decoded by FFmpeg. Their
  frames go unchanged to the audio renderer, and the system decodes and renders them, Atmos
  included. If the renderer fails or stays silent with such a track, the player switches back to
  FFmpeg decoding for that playback.
- **Technical information.** The overlay (Mac) and the Apple TV panel show the audio output: PCM
  with its channels or "Dolby bitstream", the output's channel count and, on tvOS and iOS, the
  system's rendering mode (stereo, surround, Dolby Audio, Dolby Atmos).
- **Debug switch.** `IPTV_AUDIOPASSTHROUGH=0` forces FFmpeg decoding, to compare.

Out of scope:
- TrueHD and DTS bitstreams: Apple has no decoder for them, so they stay PCM from FFmpeg, now
  up to 7.1. TrueHD Atmos and DTS:X objects stay lost; converting them to APAC (for example with
  SpatialAudioBridge) would be a change of its own.
- AAC, MP2 and other formats: they stay FFmpeg-decoded. They are mostly stereo, and FFmpeg is more
  tolerant of broken IPTV streams.
- A user setting for passthrough.
- A "Dolby Atmos" badge in the player beyond the technical information.
- Loudness normalisation.
- AC-4.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playback`:
  - "Technical information overlay" adds the audio output.
  - New requirements "Multichannel output" and "Dolby audio decoded by the system".

  These apply to every app through the shared player: the Apple TV and iPhone specs refer to the
  Mac's technical information and player.

## Impact

- `Packages/FernsyPlayer`:
  - `PlaybackSession+Audio.swift`: passthrough path, fallback, channel choice;
  - `CFFShim/FFShim.c`: output channels and layout, 7.1 order;
  - `PlayerEngine`: audio session on tvOS and iOS;
  - the stream info for the technical information.
- `FernsyTV`, `FernsyiOS`: session setup moves into the player (`FernsyiOSApp.swift` keeps only what
  is not audio-related).
- Test media: AC-3 5.1 and E-AC-3 7.1 clips for the local Jellyfin test server, made with
  jellyfin-ffmpeg in its container. These are only test content; the bundled FFmpeg stays
  LGPL-only, without encoders.
- DEVELOPMENT.md.
