## MODIFIED Requirements

### Requirement: DMG for direct installation
`scripts/build-dmg.sh` SHALL produce `dist/Fernsy-<version>.dmg`, ad-hoc signed by default or
with a given identity (optionally notarized, with a keychain profile or an App Store Connect
API key), after a launch smoke test that loads the FFmpeg libraries from the bundle only.

#### Scenario: Local test build
- **WHEN** the script runs with `SIGN_IDENTITY="Apple Development: …"`
- **THEN** the DMG contains an app whose keychain access survives rebuilds

#### Scenario: Notarizing with an API key
- **WHEN** the script runs with a Developer ID identity and `NOTARY_KEY`, `NOTARY_KEY_ID` and `NOTARY_ISSUER`
- **THEN** the DMG is notarized and stapled

## ADDED Requirements

### Requirement: Release build in GitHub Actions
A GitHub Action SHALL, on a `v*` tag, build FFmpeg (LGPL, cached), build the app signed with
Developer ID and hardened runtime, run the smoke test, notarize and staple the DMG, and attach
it to a GitHub release as `Fernsy.dmg` and `Fernsy-<version>.dmg`. Run manually, it SHALL
build the same DMG as a workflow artifact without a release. Signing data SHALL come only from
repository secrets.

#### Scenario: Tagging a release
- **WHEN** the tag `v1.1` is pushed on main
- **THEN** a release "Fernsy 1.1" appears with a notarized `Fernsy.dmg` that opens on another Mac without a Gatekeeper warning

#### Scenario: Missing secrets
- **WHEN** the Action runs without the signing secrets
- **THEN** it fails before building with a message naming the missing secrets
