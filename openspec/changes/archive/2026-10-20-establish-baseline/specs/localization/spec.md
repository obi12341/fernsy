## Purpose

Fernsy's user interface is available in German and English and follows the user's system
language.

## ADDED Requirements

### Requirement: German and English UI
Every user-visible string SHALL exist in German (source language) and English (US spelling);
the app SHALL use the language the user prefers in macOS, falling back to English.

#### Scenario: English system
- **WHEN** macOS is set to English
- **THEN** all menus, buttons, messages and the credits are English

### Requirement: Localized dates and numbers
Times, dates and plural forms SHALL be formatted for the user's locale.

#### Scenario: German locale
- **WHEN** the system locale is German
- **THEN** the guide shows dates like "Di., 20. Okt."
