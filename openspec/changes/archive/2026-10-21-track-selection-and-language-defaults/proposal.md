# Proposal

## Why

In the player's audio and subtitle menus the user cannot see which track is selected: the
menus mark the choice with a checkmark image, which macOS menus do not show as a selection
state, and the control bar icons look the same whether subtitles are on or off. Audio follows
the system language and subtitles always start off; there is no way to say "English audio,
German subtitles" or "only forced subtitles" once, and a choice made for one episode is lost at
the next one.

## What Changes

- Audio and subtitle menus show the selected track with a real menu checkmark; the subtitle
  icon is filled while subtitles are on; both buttons' help text names the current track.
- Settings get a section "Sprache & Untertitel" (German) / "Language & Subtitles" (English):
  - Audio: "System language" (default) or a fixed language.
  - Subtitles: "Off" (default), "Forced only", or a language.
- Every playback (IPTV live, films, series, recordings, Jellyfin) preselects tracks from these
  defaults: audio in the chosen language, else the stream's default track, else the first;
  subtitles per mode, using forced tracks for "Forced only" and full tracks for a language
  (forced tracks when the audio is already in that language).
- A track choice made in the player for a series episode (IPTV or Jellyfin) is remembered for
  that series and used for its next episodes instead of the defaults.

Out of scope:
- Jellyfin's per-user language preferences on the server (Fernsy's settings apply to all
  sources).
- Per-film or per-channel memory; subtitle styling (size, colour); several preferred languages
  in an ordered list.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `playback`: "Audio and subtitle tracks" shows the selection and preselects from the
  settings; new requirements for language defaults and the per-series track memory.

## Impact

- `Fernsy/Views/PlayerScreen.swift` (menus, icons), `Fernsy/Views/LoginView.swift` (settings
  section), `Fernsy/Player/MediaInfo.swift` (track language/forced/default),
  `Fernsy/Player/PlaybackSession.swift` (preselection), `Fernsy/Player/PlayerEngine.swift`,
  `Fernsy/App/AppModel.swift` (series memory), `Fernsy/Jellyfin/JellyfinPlayback.swift`
  (transcode menus, external subtitles), `Localizable.xcstrings`, `README.md`.
- Stored settings: two new UserDefaults keys and a small per-series dictionary.
