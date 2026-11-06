# Design

## Context

- **Audio path today** (`PlaybackSession+Audio.swift`, `CFFShim/FFShim.c`):
  - libavcodec decodes every audio track; swresample converts it to float32.
  - `ffs_output_channels` gives 6 channels for sources with 6 or more, otherwise 2. 7.1 is mixed
    down to 5.1, with `rematrix_maxval` 1.0 against clipping.
  - The audio thread collects blocks of at least 20 ms (shorter buffers make
    `AVSampleBufferAudioRenderer` silent, see `add-dolby-vision-playback`), tags them
    `kAudioChannelLayoutTag_MPEG_5_1_A` or stereo, and enqueues them on an
    `AVSampleBufferAudioRenderer` driven by the session's `AVSampleBufferRenderSynchronizer`.
- **Audio session.** tvOS sets none. iOS sets `.playback` / `.moviePlayback` at launch
  (`FernsyiOSApp`). macOS has no `AVAudioSession`.
- **Dolby's guide.** "Dolby Atmos and Dolby Audio over AirPlay – Application Developer Guide",
  Dec 2024. It states:
  - Dolby Digital (up to 5.1) and Dolby Digital Plus (up to 7.1, and Atmos as E-AC-3 with JOC) are
    decoded natively on iOS, iPadOS and tvOS 18+.
  - Apps should hand the bitstream to `AVSampleBufferAudioRenderer` +
    `AVSampleBufferRenderSynchronizer`, the "flexible enhanced buffering" path.
  - `AVAudioSession.supportedOutputChannelLayouts` lists the output's layouts (Atmos 5.1.2 to 7.1.4,
    5.1, 7.1) only while the session is active; `renderingCapabilitiesChangeNotification` reports
    changes.
  - `AVAudioSession.renderingMode` (`renderingModeChangeNotification`) reports monoStereo,
    surround, spatialAudio, dolbyAudio or dolbyAtmos. Dolby Atmos is reported only for a native
    bitstream, never for PCM an app decoded.
  - 5.1 PCM from a decoder must be tagged `kAudioChannelLayoutTag_MPEG_5_1_A`, or AirPlay gets the
    channels in the wrong order.

  The guide is written for AirPlay. The session APIs are the same for HDMI on Apple TV; that HDMI
  behaves alike is plausible but verified only by task 4.
- **Reference implementation.** KSPlayer 2.3.4 (FFmpeg + `AVSampleBufferAudioRenderer`, open source
  up to that version):
  - category `.playback` / `.moviePlayback` with the long-form policy, then `setActive(true)`;
  - output channels = min(source, `maximumOutputNumberOfChannels`), then
    `setPreferredOutputNumberOfChannels`;
  - `setSupportsMultichannelContent` when the route has spatial audio;
  - `allowedAudioSpatializationFormats = .monoStereoAndMultichannel` on the renderer.

  Its comment warns not to judge by `outputNumberOfChannels` or the route's channel count, which
  report 2 after a stereo item. Its issue #618 reports receivers stuck in 7.1 on tvOS 17.1, and that
  5.1 PCM over HDMI may need eARC.
- **Channel orders.** FFmpeg's 5.1 default (FL FR FC LFE SL SR) matches `MPEG_5_1_A`
  (L R C LFE Ls Rs). Its 7.1 (FL FR FC LFE BL BR SL SR) does not match `MPEG_7_1_C`
  (L R C LFE Ls Rs Rls Rrs): the side and rear pairs are swapped.

## Goals / Non-Goals

**Goals:**
- 5.1 and 7.1 reach a surround system as such on Apple TV, iPhone and iPad.
- Dolby Digital and Dolby Digital Plus, Atmos included, go to the system as a bitstream.
- Nothing gets quieter or less robust: a failing bitstream falls back to FFmpeg.
- The technical information shows what reaches the output.

**Non-Goals:**
- TrueHD or DTS bitstreams, APAC conversion, AC-4.
- Passthrough for AAC or MP2.
- A user setting, an Atmos badge, loudness normalisation.

## Decisions

### 1. One audio session owner in the player
`PlayerEngine` sets up the session on tvOS and iOS before the first playback:
- category `.playback`, mode `.moviePlayback`, policy `.longFormVideo`;
- `setActive(true)`;
- `setSupportsMultichannelContent(true)`;
- `setPreferredOutputNumberOfChannels(maximumOutputNumberOfChannels)`.

It observes `routeChangeNotification` and `renderingCapabilitiesChangeNotification` and works out
again which channel counts the output takes, from `supportedOutputChannelLayouts` and
`maximumOutputNumberOfChannels`. `FernsyiOSApp` drops its own category call. The renderer gets
`allowedAudioSpatializationFormats = .monoStereoAndMultichannel`, so AirPods spatialise 5.1/7.1.

The session calls block (activation can take seconds on a busy simulator): they run on their own
queue, never on the main thread. On the main thread at every playback start they made Apple TV
UI tests on CI run past their 120 s limit (fix/tv-ci-hangs, Nov 6, 2026).

Rejected:
- **Per-app session code:** two copies of the same rules.
- **Judging by `outputNumberOfChannels`:** it reports 2 after a stereo item, as KSPlayer found.

### 2. PCM channels from source and output, with matching layout tags
`ffs_output_channels` gets the output's maximum as well:
- 8 channels when source ≥ 8 and output ≥ 8;
- 6 when source ≥ 6 and output ≥ 6;
- otherwise 2.

For 8 channels swresample writes a custom order (FL FR FC LFE SL SR BL BR) that matches
`MPEG_7_1_C`, so the existing tag scheme (6 → `MPEG_5_1_A`, 8 → `MPEG_7_1_C`, 2 → stereo) stays
correct. The Mac keeps today's 2/6 choice plus 8 when the output device has at least 8 channels.

Rejected:
- **Channel descriptions instead of a reorder:** swresample reorders for free, and a tag is what
  Dolby recommends.

### 3. AC-3 and E-AC-3 as bitstream, with fallback
For a track whose codec is AC-3 or E-AC-3 the audio thread does not open a decoder:
- **Packets.** It wraps each packet's sync frames in a `CMSampleBuffer` with a
  `CMAudioFormatDescription` of `kAudioFormatAC3` or `kAudioFormatEnhancedAC3` (sample rate and
  channels from the codec parameters, 1536 frames per packet) and one packet description per
  frame.
- **Atmos metadata.** For E-AC-3 the format description carries the `dec3` box (built from the
  first frame's header with FFmpeg's E-AC-3 header parsing), so the system sees the JOC/Atmos
  extension.
- **Timing.** Timestamps, flushes (seek, timeshift, reconnect) and the missing-audio monitor stay
  as they are: they work on packets and the renderer, not on PCM.
- **Fallback.** When the renderer's status becomes `.failed`, or it has not started rendering 2 s
  after the first bitstream buffer while the clock runs, or 25 packets in a row have no valid
  Dolby header, the session reopens the track with FFmpeg decoding for the rest of that playback,
  and logs why. A failed `AVSampleBufferAudioRenderer` stays failed after a flush (found while
  testing it): the engine removes it from the synchronizer, adds a new one in its place
  (`AudioSink.replace`, at most three times per item) and refills the sound.
- **Debug.** `IPTV_AUDIOPASSTHROUGH=0` skips the bitstream path. The level meter
  (`IPTV_AUDIOLEVEL`) only works with PCM and says so.

Applies on all platforms, since the Mac decodes AC-3/E-AC-3 natively too. Task 1 is a spike that
settles the format description (dec3 cookie, multi-frame packets) on tvOS and macOS first.

**Spike result (task 1.1, macOS 27 and tvOS 27 simulator, AC-3 and E-AC-3 5.1 test clips):**
- One `CMSampleBuffer` per demuxed packet with one packet description, `mFramesPerPacket` 1536.
  `AVSampleBufferAudioRenderer` plays it (status rendering, no error, the synchronizer runs), and
  `AVAudioConverter` decodes it to the same channel order as FFmpeg (L R C LFE Ls Rs).
- A 5.1 stream needs no magic cookie. With one, CoreAudio takes only the whole box (32-bit size,
  `dac3`/`dec3`, payload), not the bare payload (`fmt?`), and `kAudioFormatProperty_FormatList`
  then reports the format, 6 channels and the AC-3 layout tag `0x7B0006`. The session builds that
  box from the first packet (`ffs_dolby_info`, the fields libavformat's `movenc` writes, JOC flag
  and complexity index for Atmos) and takes the layout from the format list, so the system sees
  dependent substreams (7.1) and the Atmos extension as an MP4 file would show them.
- Samples per packet come from the header (256 per audio block of the independent frames), not a
  constant: E-AC-3 may carry fewer than 6 blocks per frame.
- `AC3HeaderInfo` is private to libavcodec: the shim keeps a copy pinned to the FFmpeg version of
  `scripts/build-ffmpeg.sh`; a unit test checks the parsed values against the test clips.

Rejected:
- **Always handing the system the undecoded track:**
  - Apple has no decoder for TrueHD, DTS, Vorbis or AC-4, and AAC in LATM would need repacking.
  - FFmpeg is far more tolerant of broken IPTV streams (see `TSAudioTap`).
- **AAC bitstream:** almost always stereo, so nothing to gain, and the most fragile in IPTV.
- **Our own Dolby decoding (Dolby SDK):** licence and cost. The system already decodes Dolby and is
  the only way to Atmos.

### 4. What the technical information shows
The audio-format row gains an output row:
- "Dolby bitstream (E-AC-3 5.1)" or "PCM 5.1";
- "output 8 ch" with the session's maximum;
- on tvOS and iOS the rendering mode in plain words ("Dolby Atmos", "Surround", "Stereo").

This row is also the diagnosis for the user's Apple TV.

## Risks / Trade-offs

- **Format details of the E-AC-3 bitstream** (dec3, frames per packet) are not documented for the
  sample-buffer path. The spike (task 1) settles them before the rest; the fallback keeps the sound
  if a stream still fails.
- **Receivers and eARC.** Some receivers take 5.1 PCM only over eARC, or stay in a mode after an
  item (KSPlayer #618). Accepted: out of the app's hands; the technical information makes it
  visible.
- **No Atmos content to test with.** jellyfin-ffmpeg cannot encode JOC. Atmos is checked by the
  user on the Apple TV with own content; the tests cover AC-3 5.1 and E-AC-3 5.1 (FFmpeg's Dolby encoders stop at 5.1) and 7.1 PCM order with a FLAC 7.1 clip.
- **Lip sync with the bitstream.** The system's decoder adds latency the synchronizer accounts for;
  checked with the test clips' sync markers by eye.
