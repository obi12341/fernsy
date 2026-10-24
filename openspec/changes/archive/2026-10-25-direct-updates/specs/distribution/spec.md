## MODIFIED Requirements

### Requirement: DMG for direct installation
`scripts/build-dmg.sh` SHALL build the "Fernsy Direct" variant (with the updater) and produce
`dist/Fernsy-<version>.dmg`, ad-hoc signed by default or with a given identity (optionally
notarized, with a keychain profile or an App Store Connect API key), after a launch smoke test
that loads the FFmpeg libraries from the bundle only.

#### Scenario: Local test build
- **WHEN** the script runs with `SIGN_IDENTITY="Apple Development: …"`
- **THEN** the DMG contains an app whose keychain access survives rebuilds

#### Scenario: Notarizing with an API key
- **WHEN** the script runs with a Developer ID identity and `NOTARY_KEY`, `NOTARY_KEY_ID` and `NOTARY_ISSUER`
- **THEN** the DMG is notarized and stapled

## ADDED Requirements

### Requirement: Signed update feeds
For every release and nightly, CI SHALL publish a Sparkle appcast signed with the EdDSA key
from the secret `SPARKLE_ED_PRIVATE_KEY`: the release's `appcast.xml` (reached through
`releases/latest`) and the nightly's `appcast.xml`, each pointing to its DMG with the build
number as version and the release text as notes.

#### Scenario: Release published
- **WHEN** the release workflow publishes 1.2.0
- **THEN** `releases/latest/download/appcast.xml` lists 1.2.0 with its DMG, signature and notes
