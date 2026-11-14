# Spec Delta

## ADDED Requirements

### Requirement: System media controls
On Mac, iPhone, iPad and Apple TV, Fernsy SHALL show the playing item to the system as Now
Playing (title, second line, playing or paused, live or position and duration) and follow the
system's play and pause commands for every source like its own pause button. On-demand media
SHALL also follow skip and position commands. When playback stops, Fernsy SHALL leave Now Playing.

#### Scenario: AirPods taken out
- **WHEN** a channel or film plays through AirPods with automatic ear detection and the user takes them out of the ear
- **THEN** Fernsy pauses, and putting them back in resumes playback where it paused (live TV time-shifted)

#### Scenario: Lock Screen and Control Center
- **WHEN** a film plays on an iPhone in Picture in Picture and the user opens Control Center
- **THEN** it shows the film's title, position and duration, and its pause, skip and slider control Fernsy's playback

#### Scenario: Media key on the Mac
- **WHEN** a channel plays on the Mac and the user presses the play/pause media key while another app is in front
- **THEN** Fernsy pauses, and pressing it again resumes playback

#### Scenario: Live TV in Now Playing
- **WHEN** a live channel plays
- **THEN** Now Playing names the channel and shows it as live, without skip buttons or a position slider

#### Scenario: Pausing live TV from the system
- **WHEN** a live channel plays and the system sends pause (AirPods, Control Center, media key)
- **THEN** playback pauses and continues time-shifted from that point on play, as with the player's pause button

#### Scenario: Second line
- **WHEN** an episode, a recording or a live channel plays
- **THEN** Now Playing's second line shows the series, the channel and time, or the channel's current show as the player shows them

#### Scenario: Apple TV remote unchanged
- **WHEN** the Siri Remote's play/pause button is pressed once in the Apple TV player
- **THEN** playback toggles exactly once

#### Scenario: Playback stopped
- **WHEN** the user closes the player
- **THEN** Fernsy no longer appears as Now Playing and the media keys go back to other apps
