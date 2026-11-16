# Spec Delta

## ADDED Requirements

### Requirement: Next episode and skipping on iPhone and iPad
Jellyfin episodes SHALL show the next episode at their credits and offer to skip intros and
recaps under the Mac's rules; the skip button SHALL also show while the player controls are
hidden.

#### Scenario: Next episode at the credits
- **WHEN** a Jellyfin episode reaches its final credits and the next one exists
- **THEN** the player shows the next episode with its image and a countdown while the credits play

#### Scenario: Skip button with hidden controls
- **WHEN** a Jellyfin episode's intro plays and the player controls are hidden
- **THEN** the Skip Intro button shows, and tapping it continues playback at the end of the intro
