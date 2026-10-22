## MODIFIED Requirements

### Requirement: Transport controls and keyboard
The player SHALL offer play/pause (Space), mute (M), volume (+/−, remembered), full screen
(F, double-click, Esc to leave) and technical info (I). On-demand media SHALL seek ±10 s
(←/→) and ±60 s (⇧←/⇧→) and offer a scrub bar. Controls hide after 3 s without activity, but
never while the user drags the scrub bar, the timeshift bar or the volume slider.

#### Scenario: Seeking a movie
- **WHEN** the user presses ⇧→ during a movie
- **THEN** playback continues one minute later

#### Scenario: Holding the scrub bar
- **WHEN** the user drags the scrub bar and keeps the mouse button down for 10 s
- **THEN** the controls stay visible, and they hide 3 s after the button is released
