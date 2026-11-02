## MODIFIED Requirements

### Requirement: Store texts within limits
Store texts SHALL be kept locally in `docs/app-store.md` (git-ignored, not published) in German and
English and stay within App Store Connect limits: the app's name and subtitle, and per platform
(Mac, iPhone/iPad, Apple TV) the promotional text, description, keywords and what's new, plus the
lines of text used in the header and search results images.

#### Scenario: Checking texts
- **WHEN** `python3 scripts/check-store-texts.py` runs
- **THEN** every field of every platform is reported within its character limit

#### Scenario: Texts for a new platform
- **WHEN** the iPhone/iPad or Apple TV version is prepared in App Store Connect
- **THEN** `docs/app-store.md` has that platform's promotional text, description, keywords and what's new in German and English, describing only what the app on that platform can do
