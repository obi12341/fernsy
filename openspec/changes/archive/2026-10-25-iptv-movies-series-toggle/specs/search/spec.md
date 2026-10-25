## MODIFIED Requirements

### Requirement: Same exclusions as the sections
The search SHALL NOT find what the sections hide: hidden channels and categories, adult
categories while they are not enabled in Settings, and the IPTV account's films or series
while they are switched off in Settings › Accounts.

#### Scenario: Adult category
- **WHEN** adult categories are disabled and a film in such a category matches the query
- **THEN** it is not in the results

#### Scenario: IPTV films switched off
- **WHEN** "Filme" is switched off and the user searches for a title that the IPTV provider and Jellyfin both have
- **THEN** only the Jellyfin film is in the results
