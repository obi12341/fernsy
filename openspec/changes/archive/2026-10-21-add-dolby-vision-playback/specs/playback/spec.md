## ADDED Requirements

### Requirement: Dolby Vision
Video streams in MKV or MP4 files with a Dolby Vision profile 5 or profile 8 configuration
SHALL be shown as Dolby Vision through macOS, in HDR on HDR displays and mapped to the display
otherwise. The info overlay SHALL name the Dolby Vision profile and whether it is shown as
Dolby Vision.

#### Scenario: Profile 5 film
- **WHEN** the user plays a Dolby Vision profile 5 file
- **THEN** the colours match the film (no green or pink tint) and the info overlay shows
  "Dolby Vision 5"

#### Scenario: Profile 8 episode
- **WHEN** the user plays a Dolby Vision profile 8.1 episode
- **THEN** it plays as Dolby Vision and seeking, pausing and subtitles work as for HDR10

### Requirement: Dolby Vision fallback
When this Mac cannot decode a stream as Dolby Vision, profile 8 SHALL play its HDR10 base layer
and profile 5 SHALL be reported as not playable locally. Profile 7 SHALL play its HDR10 base
layer.

#### Scenario: Profile 7 film
- **WHEN** the user plays a dual-layer profile 7 film
- **THEN** it plays its HDR10 base layer as before and the overlay says so

#### Scenario: No Dolby Vision decoding
- **WHEN** this Mac cannot decode Dolby Vision and the user plays a profile 8 episode
- **THEN** it plays its HDR10 base layer
