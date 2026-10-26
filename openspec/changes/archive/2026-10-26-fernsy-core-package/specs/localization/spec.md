## MODIFIED Requirements

### Requirement: German and English UI
Every user-visible string SHALL have English (US spelling) as its source text and a German
translation; the app SHALL use the language the user prefers in macOS, falling back to
English for languages Fernsy does not have. Adding a language SHALL need translations only,
no change in the code.

#### Scenario: English system
- **WHEN** macOS is set to English
- **THEN** all menus, buttons, messages and the credits are English

#### Scenario: German system
- **WHEN** macOS is set to German
- **THEN** all menus, buttons, messages and the credits are German, with the same wording as before

#### Scenario: Language Fernsy does not have
- **WHEN** macOS is set to French
- **THEN** Fernsy appears in English

#### Scenario: A string without German translation
- **WHEN** a commit adds a user-visible string to a catalog without a German translation
- **THEN** the automated tests fail and name the string
