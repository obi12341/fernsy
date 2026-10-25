## ADDED Requirements

### Requirement: Decoder recovery
When the video decoder reports that it needs a restart (for example after the Mac wakes from
sleep, a display or GPU change, or broken data in the stream), the player SHALL recover by
itself: it flushes the video output and resumes from the next key frame at the current
position, without the user switching channels. Frames that fail to decode SHALL be counted in
the technical information overlay; playback continues.

#### Scenario: Picture after waking the Mac
- **WHEN** a channel plays, the Mac sleeps and wakes up, and the decoder reports that it needs a flush
- **THEN** the picture continues within a few seconds without the user doing anything

#### Scenario: Broken frames
- **WHEN** a stream delivers frames that cannot be decoded
- **THEN** playback continues and the technical information shows the number of failed frames

#### Scenario: Audio output changes
- **WHEN** the user switches the audio output (for example to AirPods) during playback
- **THEN** sound continues on the new output at the current position
