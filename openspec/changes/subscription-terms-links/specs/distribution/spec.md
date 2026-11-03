## MODIFIED Requirements

### Requirement: Store texts within limits
Store texts SHALL be kept locally in `docs/app-store.md` (git-ignored, not published) in German and
English and stay within App Store Connect limits: the app's name and subtitle, and per platform
(Mac, iPhone/iPad, Apple TV) the promotional text, description, keywords and, from a platform's
second version on, what's new, plus the
lines of text used in the header and search results images. Every description of an app that sells
the subscription SHALL end with a subscription note and functional links to the Terms of Use
(Apple's standard EULA) and the privacy policy.

#### Scenario: Checking texts
- **WHEN** `python3 scripts/check-store-texts.py` runs
- **THEN** every field of every platform is reported within its character limit

#### Scenario: Texts for a new platform
- **WHEN** the iPhone/iPad or Apple TV version is prepared in App Store Connect
- **THEN** `docs/app-store.md` has that platform's promotional text, description and keywords in German and English, describing only what the app on that platform can do

#### Scenario: Terms link in the description
- **WHEN** App Review checks a version that offers Fernsy Cloud
- **THEN** its description in every localization links Apple's standard EULA and the privacy policy
