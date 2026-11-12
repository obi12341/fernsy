# Spec Delta

## ADDED Requirements

### Requirement: One show at a time per channel
A channel's programme SHALL have at most one show at any time. When the provider's listings
for a channel overlap, Fernsy SHALL keep the largest set of listings that do not overlap and
drop the others; among overlapping listings the one that ends first is kept. The resulting
programme SHALL be the one used wherever shows are read – the guide grid, now and next, search,
the assistant and the MCP tools – on Mac, Apple TV, iPhone and iPad.

#### Scenario: Two versions of the same schedule
- **WHEN** the provider lists "Osasuna - Atlético" from 18:15 to 20:35 and again from 18:25 to
  20:55, and "Top Goals" from 20:35 to 20:45
- **THEN** the channel's row shows "Osasuna - Atlético" once, from 18:15 to 20:35, followed by
  "Top Goals", and no cell lies on top of another

#### Scenario: Placeholder across real shows
- **WHEN** the provider lists a placeholder "Fußball: TBC - TBC" from 09:50 to 12:25 and real
  shows from 09:00 to 10:25, 10:25 to 10:35 and 10:35 to 12:25
- **THEN** the row shows the three real shows and not the placeholder

#### Scenario: The same show listed twice
- **WHEN** the provider lists the same show twice with starts twenty seconds apart
- **THEN** the row and the search results show it once

#### Scenario: Now and next
- **WHEN** the show running now is listed a second time with a start ten minutes later
- **THEN** "next" names the show after the running one, not its second listing

#### Scenario: Programme cached before
- **WHEN** the app opens with a cached programme that still holds overlapping listings
- **THEN** the guide shows it without overlaps, and nothing is downloaded again for that

### Requirement: Small overlaps between consecutive shows
Two listings that overlap by at most two minutes SHALL both be kept as consecutive shows; the
earlier one SHALL end where the later one starts.

#### Scenario: A show that runs a minute into the next
- **WHEN** the provider lists a show from 19:00 to 20:16 and the next one from 20:15 to 21:00
- **THEN** the guide shows both, the first from 19:00 to 20:15 and the second from 20:15 to 21:00
