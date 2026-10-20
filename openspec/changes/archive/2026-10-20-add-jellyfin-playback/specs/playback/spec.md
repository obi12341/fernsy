## MODIFIED Requirements

### Requirement: Audio and subtitle tracks
The player SHALL list all decodable audio tracks and subtitle tracks – text subtitles and bitmap
subtitles (PGS, VobSub, DVB) –, preselect audio in the user's preferred language, and switch
tracks without restarting playback. Bitmap subtitles SHALL be drawn at their position on the
picture; several text subtitles active at the same time SHALL all be shown.

#### Scenario: Two audio languages
- **WHEN** a channel has German and English audio and the system language is English
- **THEN** English audio is selected and German can be chosen in the audio menu

#### Scenario: PGS subtitles of a Blu-ray remux
- **WHEN** the user chooses a PGS subtitle track
- **THEN** the subtitles appear as on the disc, at their position and in time with the picture

#### Scenario: Two speakers at once
- **WHEN** two text subtitle cues overlap in time
- **THEN** both lines are shown
