## MODIFIED Requirements

### Requirement: Following live stays close to live
While following live, playback SHALL never jump on its own. It SHALL keep the distance to the
newest data it settled at after starting – a provider's initial backlog burst is played and
playback is still shown as live. When it falls more than about 12 s further behind than that
distance for several seconds (e.g. after stalls), it SHALL leave the live state and show how far
behind it is; only the user's "Live" action returns to the live edge.

#### Scenario: Backlog at connect
- **WHEN** the provider sends 20 s of backlog spread over the first seconds after the channel
  starts
- **THEN** playback runs on without a jump and the player shows "LIVE"

#### Scenario: Falling further behind
- **WHEN** playback, following live, falls 15 s further behind than where it settled after
  starting
- **THEN** it keeps playing without a jump and the badge changes from "LIVE" to the time behind

#### Scenario: Back to live
- **WHEN** the user clicks the badge showing the time behind
- **THEN** playback goes to the live edge (newest data minus the start lead) and shows "LIVE"
