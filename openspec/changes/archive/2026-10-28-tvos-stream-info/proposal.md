# Proposal

## Why

On the Mac, I shows the technical information overlay (codecs, decoder, buffer, reconnects,
dropped duplicates, a two-minute buffer chart). The Apple TV app plays with the same engine but
has no way to show it, so a stutter or a repeated scene on a real Apple TV cannot be looked
into on the device; today only the debug MCP's `playback_diagnostics` reaches these numbers.

## What Changes

- A "Technische Infos" switch under Settings › Wiedergabe on Apple TV. While it is on, every
  player (live, timeshift, films and episodes, Jellyfin, recordings) shows the technical
  information panel in the top-right corner, updated once per second, over the picture and
  under the player overlay.
- The panel shows what the Mac's overlay shows (container, codecs, resolution, frame rate,
  decoder, pixel format, dynamic range, deinterlacing, audio, bit rate, buffer, timeshift
  buffer, connection and startup time, reconnects, rebuffers, dropped frames and duplicates,
  decode errors, playback method for Jellyfin) and the two-minute buffer chart, sized for TV.
- The list of rows moves into the shared player package, so the Mac and the Apple TV show the
  same rows from one place.
- Debug builds: `IPTV_SHOWINFO` turns the panel on, as on the Mac.

Out of scope:
- New values the Mac overlay does not show.
- A per-playback toggle on the remote (no free button; see design).
- Changes to the Mac overlay's look or its I key.

## Capabilities

### New Capabilities

### Modified Capabilities
- `apple-tv`: a requirement for the technical information panel on Apple TV and its switch.

## Impact

- `Packages/FernsyPlayer`: the info rows (labels and formatted values) as shared code with
  their strings in the package's catalog.
- `Fernsy/Views/PlayerScreen.swift` (`StatsOverlay` reads the shared rows).
- `FernsyTV/Screens/SettingsScreen.swift`, `PlayerScreen.swift`, `VODPlayerScreen.swift`,
  `RecordingsScreen.swift` (recording player); a TV panel view under `FernsyTV/`.
- German strings for the switch and any moved labels.
