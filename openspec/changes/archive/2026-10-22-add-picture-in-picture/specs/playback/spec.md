## ADDED Requirements

### Requirement: Picture in Picture
The player SHALL offer Picture in Picture (button in the controls, key P) for every source. While
it runs, the whole picture plays in the system's floating window and the player window is hidden.
"Back" returns to the player window without interrupting playback; closing the PiP window stops
playback like closing the player window.

#### Scenario: Watching while working
- **WHEN** the user starts Picture in Picture during a live channel
- **THEN** the channel keeps playing in the floating window, shown as live, and the player window disappears

#### Scenario: Controls in the PiP window
- **WHEN** the user uses the PiP window's controls
- **THEN** play/pause works for every source (pausing live TV continues time-shifted) and on-demand media skips back and forward by the system's interval

#### Scenario: Whole picture at any size
- **WHEN** the user resizes the PiP window
- **THEN** the whole picture stays visible and centred, without parts cut off or covered

#### Scenario: Back to the player
- **WHEN** the user clicks "back" in the PiP window
- **THEN** the player window reappears with the picture and playback continues at the same point

#### Scenario: Closing PiP
- **WHEN** the user closes the PiP window
- **THEN** playback stops and the stream is released as when closing the player window
