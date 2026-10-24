## ADDED Requirements

### Requirement: Pinned entries in the category column
The Live TV category column SHALL start with "Alle", "Favoriten" (the favourite channels)
and "Zuletzt gesehen" (the last 20 channels played, newest first), followed by the
provider's categories in their delivered order, flat. Hidden channels are left out of the
pinned entries like everywhere else.

#### Scenario: Recently watched
- **WHEN** the user played "Kanal Süd" and then "Nordlicht 1"
- **THEN** "Zuletzt gesehen" lists "Nordlicht 1" first and "Kanal Süd" second

#### Scenario: Favourites in Live TV
- **WHEN** the user selects "Favoriten" in the Live TV category column
- **THEN** only the favourite channels are listed, in the list and in the guide
