## MODIFIED Requirements

### Requirement: Adult categories hidden by default
Categories whose names mark them as adult content SHALL be hidden unless "Show adult
categories" is enabled in Settings. This only hides them; it is no parental lock. Settings ›
Youth protection SHALL list the categories detected as adult content with their names as
delivered.

#### Scenario: Default
- **WHEN** a provider offers a category named like "XXX" or "Adult"
- **THEN** it does not appear until the user enables the setting

#### Scenario: Checking what is hidden
- **WHEN** the user opens Settings › Youth protection
- **THEN** the detected adult categories of live TV, films and series are listed by name
