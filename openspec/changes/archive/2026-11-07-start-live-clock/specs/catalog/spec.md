## ADDED Requirements

### Requirement: Start on the Mac follows the clock
While Start is shown, Jetzt live SHALL show the show on now with its progress, moving on to the
next show within a minute of the change, and Heute Abend SHALL leave out shows that ended. The
guides of Start's channels SHALL be loaded again when they run short, as in the channel list.

#### Scenario: Start left open
- **WHEN** Start stays open while a channel's show ends at 20:15
- **THEN** by 20:16 its card in Jetzt live shows the next show without leaving Start

#### Scenario: Tonight moves on
- **WHEN** Start stays open past 21:30
- **THEN** the row turns into "Demnächst" with what starts in the next two hours
