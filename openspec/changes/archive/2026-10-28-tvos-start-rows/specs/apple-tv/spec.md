## MODIFIED Requirements

### Requirement: Start on Apple TV
Start SHALL show a large entry: the newest item to continue with its backdrop and "Fortsetzen",
or else the newest film with "Abspielen". Below it SHALL follow, each only with entries: Jetzt
live (favourite or recent channels with the show on now), Weiterschauen, Nächste Folge
(Jellyfin), Heute Abend (prime time on those channels), Zuletzt hinzugefügt, rows of the largest
film and series categories and Jellyfin genres, Deine Aufnahmen and Bestbewertet.

#### Scenario: Resuming from Start
- **WHEN** the user clicks a partly watched film in "Weiterschauen"
- **THEN** it plays from where the user stopped

#### Scenario: Nothing to continue
- **WHEN** nothing is partly watched
- **THEN** the large entry shows the newest film with "Abspielen", and "Weiterschauen" is not shown

#### Scenario: Live from Start
- **WHEN** the user clicks a channel in "Jetzt live"
- **THEN** the channel plays full screen

#### Scenario: Tonight
- **WHEN** the user clicks a show in "Heute Abend" that starts later
- **THEN** the app offers to record it

#### Scenario: Categories
- **WHEN** the provider's largest film category is "Action"
- **THEN** Start shows a row "Filme · Action" with its newest films
