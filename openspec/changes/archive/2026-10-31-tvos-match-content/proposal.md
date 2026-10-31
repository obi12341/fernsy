# Proposal

## Why

The Apple TV never switches the TV's display mode for what Fernsy plays: a 23.976 fps film runs at
the interface's 60 Hz (uneven 3:2 cadence), 50 Hz German TV judders at 60 Hz, and HDR or Dolby
Vision is mapped to SDR when the interface runs in SDR. tvOS only switches when the app asks:
AVPlayer does this by itself, but Fernsy renders FFmpeg frames into an
`AVSampleBufferDisplayLayer`, so it has to hand tvOS the frame rate and dynamic range itself
(`AVDisplayCriteria`). The user noticed that the TV keeps its mode when a film starts.

## What Changes

- The Apple TV player tells tvOS the frame rate and dynamic range of what it shows (films,
  episodes, Jellyfin items, recordings, cloud recordings, catch-up and live channels), so a TV
  with "Match Content" switches to the matching mode. Leaving the player hands the mode back to
  the system.
- The frame rate is the one shown: interlaced TV, deinterlaced to double rate, asks for 50 Hz,
  not 25. The dynamic range is the one shown: Dolby Vision mapped to HDR10 asks for HDR10.
- Switching live channels in the player asks again only when the frame rate or dynamic range
  changes, so zapping between channels of the same kind keeps the mode.
- Playback waits while the TV switches, so the start of an item is not lost in the black
  picture of the switch.
- The Live TV preview pane does not ask for a mode: only the full-screen player does.
- New option "Match Frame Rate and Dynamic Range" per account: in Settings › IPTV Account for
  everything the IPTV account plays (live TV, catch-up, films, series, recordings and cloud
  recordings), off by default, because switching while zapping gets in the way; and in
  Settings › Jellyfin Server for Jellyfin items, on by default. While an account's option is
  off, Fernsy never asks for a mode for its items. tvOS still only switches when "Match
  Content" is on in the Apple TV's own settings; the option's note says so.

Out of scope:
- **Mac, iPad and iPhone.** Only tvOS (and visionOS) let an app ask for a display mode;
  macOS, iPadOS and iOS have no such interface. HDR and Dolby Vision already show in HDR there
  through the system (EDR), and ProMotion displays choose their rate themselves. Changing the
  Mac's display mode for an external TV through CoreGraphics is rejected in design.md.
- Changing the Apple TV's own "Match Content" setting from Fernsy (apps cannot).
- Audio format or sample-rate matching.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: a new requirement for passing the frame rate and dynamic range to tvOS, with the
  per-account settings that turn it on and off.

## Impact

- `Packages/FernsyPlayer`: `PlaybackSession` and `PlayerEngine` publish what the shown video
  is (output frame rate after deinterlacing, format description with colour attachments or
  the Dolby Vision format) and can hold the clock while a mode switch runs.
- `FernsyTV`: a small display-mode controller using the window's `avDisplayManager`, wired to
  the full-screen player only; the new option in `SettingsScreen.swift`; strings in
  `FernsyTV/Localizable.xcstrings` (English and German).
- Mac and iOS apps: unchanged.
- No new entitlement. Testing needs the real Apple TV and TV: the simulator does not switch
  modes.
