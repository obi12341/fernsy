## MODIFIED Requirements

### Requirement: Rewind and seek in live TV
For live TV the player SHALL offer a timeline over the buffered range with clock times
below and the shows' boundaries and titles above, ←/→ for ±10 s, ⇧←/⇧→ for ±60 s and
−10/+10 buttons; seeking forward is limited to the live edge. The timeline SHALL take the
mouse on its knob and anywhere along its bar, like the volume slider.

#### Scenario: Rewinding two minutes
- **WHEN** the user presses ⇧← twice while watching live
- **THEN** playback jumps two minutes back and the timeline shows the matching clock time

#### Scenario: Where a show began
- **WHEN** the buffer reaches back across the start of the current show
- **THEN** the timeline marks that start and shows the show's title next to it

#### Scenario: Dragging the knob
- **WHEN** the user presses the mouse on the timeline's knob, drags it five minutes to the left and releases it
- **THEN** the knob follows the pointer during the drag and playback continues five minutes earlier

#### Scenario: Clock times after a seek
- **WHEN** the user jumps back 10 minutes
- **THEN** the clock times and show marks on the timeline stay where they were
