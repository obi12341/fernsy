## MODIFIED Requirements

### Requirement: Audio and subtitle tracks
The player SHALL list all decodable audio tracks and subtitle tracks – text subtitles and bitmap
subtitles (PGS, VobSub, DVB) –, preselect them from the language settings, and switch tracks
without restarting playback. The menus SHALL mark the selected track (or "Off") with a
checkmark, and the control bar SHALL show whether subtitles are on. Bitmap subtitles SHALL be
drawn at their position on the picture; several text subtitles active at the same time SHALL
all be shown.

#### Scenario: Two audio languages
- **WHEN** a channel has German and English audio, the audio setting is "System language" and
  the system language is English
- **THEN** English audio is selected and German can be chosen in the audio menu

#### Scenario: Seeing the selection
- **WHEN** the user opens the audio or subtitle menu
- **THEN** the selected track (or "Off") carries a checkmark, and the subtitle button looks
  different while subtitles are on

#### Scenario: PGS subtitles of a Blu-ray remux
- **WHEN** the user chooses a PGS subtitle track
- **THEN** the subtitles appear as on the disc, at their position and in time with the picture

#### Scenario: Two speakers at once
- **WHEN** two text subtitle cues overlap in time
- **THEN** both lines are shown

## ADDED Requirements

### Requirement: Language defaults
Settings SHALL offer a default audio language ("System language" or a fixed language) and a
default subtitle mode ("Off", "Forced only" or a language). Each playback SHALL preselect audio
in that language, else the stream's default track, else the first.

#### Scenario: English audio with German subtitles
- **WHEN** the settings say audio English and subtitles German and a film has both
- **THEN** it starts with English audio and full German subtitles

### Requirement: Subtitle defaults
Subtitles SHALL follow the subtitle mode: none for "Off"; the forced track in the audio's
language for "Forced only"; for a language, its full track, or its forced track when the audio
is already in that language. Without a matching track subtitles SHALL stay off.

#### Scenario: Forced only
- **WHEN** subtitles are set to "Forced only" and a German-dubbed film has a German forced track
- **THEN** only the forced track is shown

#### Scenario: No matching track
- **WHEN** the subtitle language is French and the film has no French subtitles
- **THEN** subtitles stay off and the menu shows "Off" checked

### Requirement: Track choice per series
A track choice the user makes in the player during a series episode (IPTV or Jellyfin) SHALL be
remembered by language for that series and SHALL preselect the tracks of its following
episodes instead of the defaults; films, channels and recordings SHALL always start from the
defaults.

#### Scenario: Binge watching in English
- **WHEN** the user switches episode 1 of a series to English audio and German subtitles and
  then plays episode 2
- **THEN** episode 2 starts with English audio and German subtitles
