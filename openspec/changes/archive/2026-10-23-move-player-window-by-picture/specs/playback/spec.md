## ADDED Requirements

### Requirement: Moving the window by the picture
The player window SHALL move when the user presses anywhere on the picture and drags, outside
full screen. Pressing without moving SHALL keep showing the controls, and a double-click SHALL
keep toggling full screen. The controls and other interactive overlays keep their own clicks
and do not move the window.

#### Scenario: Dragging the picture
- **WHEN** the user presses in the middle of the picture and drags 200 points to the right
- **THEN** the player window follows the pointer

#### Scenario: Click without dragging
- **WHEN** the user clicks on the picture without moving the pointer
- **THEN** the window stays where it is and the controls appear

#### Scenario: Double-click
- **WHEN** the user double-clicks on the picture
- **THEN** the player toggles full screen and the window is not moved

#### Scenario: Dragging a slider
- **WHEN** the user drags the scrub bar or the volume slider
- **THEN** the slider moves and the window stays where it is
