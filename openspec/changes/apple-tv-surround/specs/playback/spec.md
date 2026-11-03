## MODIFIED Requirements

### Requirement: Technical information overlay
The info overlay SHALL show container, codecs, resolution, frame rate, decoder, pixel
format, dynamic range, deinterlacing, audio format, audio output, bit rate, buffer levels,
connection and startup time, reconnects, rebuffers, dropped frames and a two-minute buffer chart.
The audio output SHALL say whether the system decodes a Dolby bitstream or Fernsy plays PCM with
how many channels, the output's channel count, and on Apple TV, iPhone and iPad the system's
rendering mode.

#### Scenario: Pressing I
- **WHEN** the user presses I during playback
- **THEN** the overlay appears and updates once per second

#### Scenario: Dolby Atmos on Apple TV
- **WHEN** a film with an E-AC-3 Atmos track plays on an Apple TV connected to an Atmos receiver
- **THEN** the technical information shows "Dolby bitstream" and the rendering mode "Dolby Atmos"

## ADDED Requirements

### Requirement: Multichannel output
On Apple TV, iPhone and iPad the player SHALL set up the audio session for movie playback with
multichannel content and ask for as many output channels as the current output supports,
following route changes. Audio that Fernsy decodes itself SHALL be output as stereo, 5.1 or 7.1,
as the source has them and the output supports them, with a channel layout that matches the order
of the samples.

#### Scenario: 5.1 on a surround system
- **WHEN** a channel with AC-3 5.1 sound plays on an Apple TV connected to a 5.1 receiver, with passthrough off
- **THEN** the receiver gets 5.1 multichannel PCM, not stereo

#### Scenario: 7.1 from Jellyfin
- **WHEN** a film with a TrueHD 7.1 track plays on an Apple TV whose output supports 7.1
- **THEN** all eight channels reach the output in the right places, the side and rear surrounds not swapped

#### Scenario: Stereo output
- **WHEN** a 5.1 track that Fernsy decodes itself plays on an output that supports only stereo
- **THEN** it is mixed down to stereo without clipping

### Requirement: Dolby audio decoded by the system
AC-3 and E-AC-3 tracks SHALL go to the system unchanged, so that it decodes and renders them for
the output, Dolby Atmos included. When the system fails to play such a track, the player SHALL
continue that playback with Fernsy's own decoding, without stopping the picture.

#### Scenario: Atmos film
- **WHEN** a film with an E-AC-3 track with Dolby Atmos plays on an Apple TV connected to an Atmos receiver
- **THEN** the receiver plays Dolby Atmos

#### Scenario: Broken Dolby stream
- **WHEN** a live channel's AC-3 track cannot be played by the system
- **THEN** the sound continues within a few seconds from Fernsy's own decoding and the technical information shows PCM

#### Scenario: Other formats unchanged
- **WHEN** a channel with AAC stereo plays
- **THEN** Fernsy decodes it itself as before
