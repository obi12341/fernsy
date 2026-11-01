## ADDED Requirements

### Requirement: Episode codes
Wherever the Mac, Apple TV or iPhone/iPad app names an episode by season and number, it SHALL
write the same code: "S<season> F<episode>" in German and "S<season> E<episode>" in English, with
a space between the two parts. Machine-readable answers (the MCP tools) are not affected.

#### Scenario: German
- **WHEN** the system language is German and Weiterschauen shows episode 2 of season 1
- **THEN** its line reads "S1 F2" on the Mac, the Apple TV and the iPad

#### Scenario: English
- **WHEN** the system language is English and a series page offers its next episode
- **THEN** the code reads "S1 E2", not "S1 F2"
