## MODIFIED Requirements

### Requirement: Transport controls and keyboard
The player SHALL offer play/pause (Space), mute (M), volume (+/−, remembered), full screen
(F, double-click, Esc to leave) and technical info (I). On-demand media SHALL seek ±10 s
(←/→) and ±60 s (⇧←/⇧→) and offer a scrub bar that takes the mouse on its knob and anywhere
along its bar, like the volume slider. Controls hide after 3 s without activity, but
never while the user drags the scrub bar, the timeshift bar or the volume slider.

#### Scenario: Seeking a movie
- **WHEN** the user presses ⇧→ during a movie
- **THEN** playback continues one minute later

#### Scenario: Holding the scrub bar
- **WHEN** the user drags the scrub bar and keeps the mouse button down for 10 s
- **THEN** the controls stay visible, and they hide 3 s after the button is released

#### Scenario: Grabbing the scrub bar's knob
- **WHEN** the user presses the mouse on the film's scrub bar knob and drags it
- **THEN** the knob follows the pointer and playback continues where it is released
