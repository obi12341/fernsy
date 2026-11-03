# Tasks

## 1. Spike

- [ ] 1.1 Bitstream spike in a test build: an AC-3 5.1 and an E-AC-3 7.1 clip (task 3.1) as `CMSampleBuffer`s with `kAudioFormatAC3`/`kAudioFormatEnhancedAC3` on `AVSampleBufferAudioRenderer`, on the tvOS simulator and the Mac; settle the format description (dec3 cookie, frames per packet); record the result in design.md

## 2. Implementation

- [ ] 2.1 Audio session in `PlayerEngine` for tvOS and iOS (category, active, multichannel, preferred channels, route and rendering-capability notifications); `FernsyiOSApp` without its own category; renderer spatialization formats
- [ ] 2.2 `ffs_output_channels` with the output's maximum (2/6/8), 7.1 written in `MPEG_7_1_C` order, layout tag per count; unit tests for the channel choice and the 7.1 order
- [ ] 2.3 Bitstream path for AC-3/E-AC-3 in `PlaybackSession+Audio.swift` with fallback to FFmpeg (renderer failed, or nothing audible after 2 s); `IPTV_AUDIOPASSTHROUGH=0`; logging
- [ ] 2.4 Technical information: audio output row (bitstream/PCM, channels, output channels, rendering mode) on Mac, Apple TV, iPhone/iPad; German strings

## 3. Verification

- [ ] 3.1 Test clips for `scripts/jellyfin-test-server.sh`: AC-3 5.1 and E-AC-3 7.1 (jellyfin-ffmpeg in its container), and a TrueHD 7.1 clip if its encoder allows
- [ ] 3.2 Local Jellyfin test server: the clips play with sound on Mac (Fernsy Dev) and tvOS simulator, technical information shows "Dolby bitstream" for AC-3/E-AC-3 and "PCM 7.1" for TrueHD; with `IPTV_AUDIOPASSTHROUGH=0` all PCM; a corrupted AC-3 clip falls back to PCM; demo server live channels (AAC) unchanged; `scripts/vm.sh scripts/test.sh` and the Apple TV UI tests
- [ ] 3.3 User on the Apple TV with a surround receiver (Release build): AC-3 5.1 channel shows multichannel on the receiver, an E-AC-3 Atmos film shows Dolby Atmos and the technical information says so

## 4. Wrap-up

- [ ] 4.1 DEVELOPMENT.md (audio path, debug switch, test clips); `openspec validate --all --strict`; archive, merge into `main`, push
