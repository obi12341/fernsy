# Design

## Context

- Player menus (`PlayerScreen`, control bar): `Menu` with one `Button` per track; the selected
  one gets `Label(title, systemImage: "checkmark")`. macOS menus treat that as an item icon, not
  as the on/off state, and may hide item icons – the selection is invisible. The subtitle button
  is the same `captions.bubble` icon whether subtitles are on or off.
- Preselection: `PlaybackSession.openInput` takes the first audio track whose language matches
  `Locale.preferredLanguages.first` (`MediaNames.isPreferred`), else FFmpeg's best stream;
  subtitles start off. `MediaTrack` is only `{id, title}`.
- Jellyfin: `JellyfinPlayback` lists external subtitles (ids 10000+/20000+) and, in a
  transcode, the source's tracks by Jellyfin index; it maps FFmpeg ↔ Jellyfin indices.
  `JFMediaStream` has `language`, `isDefault`, `isExternal`, `isTextSubtitleStream`, title.
- Many files mark forced subtitles only in the title ("German Forced", "FORCED SRT") and not in
  the stream disposition.
- Debug builds share UserDefaults with the user's installed app (tests must not change the
  user's settings).

## Goals / Non-Goals

**Goals:** visible selection; one place for language defaults; the same choice rules for every
source; series keep the user's choice.

**Non-Goals:** see proposal.

## Decisions

### Track metadata
`MediaTrack` gains `language: String?` (ISO 639-1, normalised from 639-2 B/T codes as
`MediaNames` already does), `isForced: Bool` and `isDefault: Bool`. Forced = FFmpeg
`AV_DISPOSITION_FORCED`, Jellyfin `IsForced`, or a title containing "forced" / "erzwungen"
(case-insensitive). Default = `AV_DISPOSITION_DEFAULT` / Jellyfin `IsDefault`.

### One chooser for all sources
`TrackChooser.choose(audio:subtitles:preferences:) -> (audio: Int32?, subtitle: Int32?)`, a pure
function:
- Audio: language match (preferring the default-flagged one among several), else the default
  track, else the first.
- Subtitles: `.off` → nil. `.forcedOnly` → forced track in the chosen audio's language.
  `.language(x)` → when the audio is in `x`, the forced track in `x` (nil if none); otherwise
  the full (non-forced) track in `x`, preferring the default-flagged one, else a forced one in
  `x`, else nil.
- Unknown audio language ("und"/missing) counts as "not x".
`TrackPreferences { audioLanguage: String? (nil = system), subtitles: off | forcedOnly |
language(String) }` is resolved by `AppModel` for each `PlayItem`: series memory if present,
else settings.

### Where the choice is applied
- `PlaybackSession.openInput` applies the chooser to its own track lists and sets `audioIndex`
  and `subtitleIndex` before the first packet – no extra seek. `MediaInfo.selectedSubtitle`
  reflects it.
- Jellyfin decides itself, because only it knows external files: `JellyfinPlayback` runs the
  chooser over the Jellyfin streams (embedded + external) before starting, passes the result
  as the transcode request's indices, and for direct play hands the engine an explicit
  selection (FFmpeg ids via the existing index mapping) that overrides the session's own choice;
  an external text track is loaded via SRT after opening, an external bitmap track starts as a
  burn-in transcode.
- Rejected: Jellyfin's server-side language preferences – a second place to configure, and it
  would not cover IPTV.
- Rejected: storing track indices – they differ between episodes and sources; languages and the
  forced flag carry over.

### Series memory
When the user picks a track in the player during an IPTV episode (`.episode(_, seriesId)`) or a
Jellyfin episode (`item.seriesId`), `AppModel` stores `{audioLanguage, subtitles}` under
`iptv.<seriesId>` / `jellyfin.<seriesId>` in one UserDefaults dictionary (`tracks.series`,
capped at 200 entries, oldest dropped). Only explicit menu choices are stored, not the automatic
preselection. A picked full subtitle track is stored as `full(<language>)`, which the chooser
keeps even when the audio is in the same language (otherwise "German audio + full German
subtitles" would come back as the forced track); a picked forced track in the audio's language
is stored as "Forced only". `full` is not offered in the settings.

### Menus and icons
Each menu holds an inline `Picker` bound to the selected id (`nil` = "Off" for subtitles) – real
menu checkmarks. Subtitle button: `captions.bubble.fill` while a subtitle is on. Help texts:
"Tonspur: <title>" / "Untertitel: <title or Aus>".

### Settings
Section "Sprache & Untertitel" in `SettingsView`: picker "Tonspur" ("Systemsprache (<name>)" +
fixed list of about 20 common languages, names via `Locale`), picker "Untertitel" ("Aus", "Nur
erzwungene", then the same language list). Keys `tracks.audioLanguage` ("" = system) and
`tracks.subtitles` ("off", "forced", or a language code).

### Testing without touching the user's settings
Debug-only overrides: `IPTV_AUDIOLANG=<code|system>`, `IPTV_SUBTITLES=<off|forced|code>` replace
the stored settings for the run; `IPTV_TRACKSTORE=test` makes the series memory use a separate
key (`tracks.series.test`), removed after the tests. `IPTV_AUTOPLAY=episode:<series>:<n>` plays
the n-th episode of an IPTV series; `IPTV_TRACKSELFTEST=1` checks the chooser rules.

## Risks / Trade-offs

- [Forced detection by title misses unusual names] → disposition and Jellyfin flags first;
  title words cover the common cases seen in the library.
- [Files with wrong language tags] → the menu still allows any choice; the series memory then
  keeps the user's pick.
- [Preselected bitmap subtitle in a Jellyfin direct play] → decoded by the player (no change);
  only external bitmap files cause a transcode, as today.
