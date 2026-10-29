## MODIFIED Requirements

### Requirement: Picture in Picture on iPhone and iPad
Live channels and on-demand items SHALL be able to continue in Picture in Picture: from the
player's button, and automatically when the user leaves the app while playing. Playback SHALL
continue with sound while in Picture in Picture; returning from it SHALL show the full-screen
player again. Leaving the app while nothing plays SHALL NOT open a Picture in Picture window.

#### Scenario: Leaving the app while watching
- **WHEN** a channel plays full screen and the user goes to the home screen
- **THEN** the channel continues in a Picture in Picture window with sound

#### Scenario: Back from Picture in Picture
- **WHEN** the user taps the button to return in the Picture in Picture window
- **THEN** Fernsy opens with the player full screen, still playing

#### Scenario: Leaving the app after closing the player
- **WHEN** the user watched a channel, closed the player, and then goes to the home screen
- **THEN** no Picture in Picture window opens
