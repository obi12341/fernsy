## MODIFIED Requirements

### Requirement: Checking for updates
The DMG build SHALL check a signed feed for newer builds once a day when automatic checks are
on (the default, switchable in Settings) and SHALL offer "Nach Updates suchen …" in the Fernsy
menu and in Settings. An update SHALL show its version and its release notes in the system
language (German, otherwise English) and offer Install, Later and Skip; it is only installed
when its EdDSA signature matches the app's key.

#### Scenario: New release available
- **WHEN** release 1.2.0 is published and the DMG build 1.1.x runs with automatic checks on
- **THEN** within a day Fernsy shows the update to 1.2.0 with its release notes

#### Scenario: Manual check, nothing new
- **WHEN** the user chooses "Nach Updates suchen …" and the newest build is installed
- **THEN** Fernsy says that it is up to date

#### Scenario: Tampered download
- **WHEN** the downloaded update's signature does not match the app's public key
- **THEN** Sparkle refuses to install it

#### Scenario: Notes in the system language
- **WHEN** the Mac's language is English and an update is offered
- **THEN** the update window shows the English release notes
