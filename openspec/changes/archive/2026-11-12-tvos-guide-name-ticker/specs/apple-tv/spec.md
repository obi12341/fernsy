# Spec Delta

## ADDED Requirements

### Requirement: Long channel names in the Apple TV guide
A channel name that does not fit the guide's channel column SHALL be shown shortened with an
ellipsis. While focus is on a cell of that channel's row, the name SHALL instead slide to its
end and back in a loop, resting briefly at both ends, so the whole name can be read. When focus
leaves the row, the name SHALL show shortened again. Names that fit SHALL not move. With Reduce
Motion on, names SHALL stay shortened.

#### Scenario: Reading a long name
- **WHEN** the user moves focus onto a show in the row of "Northern Light 1", whose name is shown
  shortened
- **THEN** after about a second the name slides to the left until its end shows, rests, slides
  back to its beginning, rests, and goes on like that

#### Scenario: Moving within the row
- **WHEN** the name of the focused row is sliding and the user moves right to the next show of
  the same channel
- **THEN** the name keeps sliding

#### Scenario: Moving on to another row
- **WHEN** the user presses Down
- **THEN** the name of the row left behind shows shortened with an ellipsis again, and the name
  of the row now focused starts to slide if it does not fit

#### Scenario: A name that fits
- **WHEN** focus is on a show of "Current TV", whose name fits the column
- **THEN** the name does not move

#### Scenario: Reduce Motion
- **WHEN** Reduce Motion is on and focus is on the row of a channel with a long name
- **THEN** the name stays shortened and does not move
