# localization Specification

## Purpose
Fernsy's user interface is available in German and English and follows the user's system
language.

## Requirements

### Requirement: German and English UI
Every user-visible string of the Mac and Apple TV apps SHALL have English with US spelling and
wording as its source text ("Movies", "Favorites", "program") and a German translation; the
apps SHALL use the language the user prefers in the system, falling back to English for
languages Fernsy does not have. Adding a language SHALL need translations only, no change in
the code.

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

#### Scenario: British spelling
- **WHEN** a commit adds an English text with "Films", "Favourite" or "programme" to a catalog
- **THEN** the automated tests fail and name the string

#### Scenario: Apple TV in English
- **WHEN** the Apple TV is set to English
- **THEN** the tab bar shows "Movies" and a channel's menu offers "Favorite"

### Requirement: Localized dates and numbers
Times, dates and plural forms SHALL be formatted for the user's locale.

#### Scenario: German locale
- **WHEN** the system locale is German
- **THEN** the guide shows dates like "Di., 20. Okt."
