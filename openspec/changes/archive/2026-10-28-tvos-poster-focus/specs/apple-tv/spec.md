## ADDED Requirements

### Requirement: Focused posters on Apple TV
A focused poster or card SHALL grow and lift as one: its artwork (or placeholder) and its badges
(Neu, source, episode count, watched checkmark, rating, progress) keep their size relative to it.
No badge SHALL get a focus effect of its own.

#### Scenario: A watched film gets focus
- **WHEN** the user moves focus onto the poster of a watched film
- **THEN** the poster grows with the checkmark in its corner, and the checkmark keeps its size relative to the poster

#### Scenario: A poster without artwork
- **WHEN** a watched film has no artwork and its placeholder gets focus
- **THEN** the placeholder grows with the checkmark, as a poster with artwork does
