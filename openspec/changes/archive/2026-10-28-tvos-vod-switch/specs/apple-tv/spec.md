## ADDED Requirements

### Requirement: Films and series switches on Apple TV
Settings › IPTV Account SHALL offer the switches "Filme" and "Serien", on by default, as on the
Mac. A switched-off kind SHALL NOT be downloaded or cached and SHALL NOT appear in the tab bar,
on Start or in the search. Its favourites, watched marks and resume positions SHALL be kept.
Switching a kind on again SHALL download it right away.

#### Scenario: Switching films off
- **WHEN** the user switches "Filme" off in Settings › IPTV Account
- **THEN** the Filme tab disappears, and Start and the search show no provider films

#### Scenario: Switching series on again
- **WHEN** "Serien" was off and the user switches it on
- **THEN** the series are downloaded and the Serien tab comes back with its earlier watched marks
