## MODIFIED Requirements

### Requirement: Release build in GitHub Actions
A GitHub Action SHALL, on a `v*` tag, build FFmpeg (LGPL, cached), build the app signed with
Developer ID and hardened runtime, run the smoke test, notarize and staple the DMG, and attach
it to a GitHub release as `Fernsy.dmg` and `Fernsy-<version>.dmg`, with German and English
notes from the `Release-Note-de`/`-en` commit trailers since the previous release tag. Run
manually, it SHALL build the same DMG as a workflow artifact. Signing data SHALL come only
from repository secrets.

#### Scenario: Tagging a release
- **WHEN** the tag `v1.1` is pushed on main
- **THEN** a release "Fernsy 1.1" appears with a notarized `Fernsy.dmg` that opens on another Mac without a Gatekeeper warning

#### Scenario: Missing secrets
- **WHEN** the Action runs without the signing secrets
- **THEN** it fails before building with a message naming the missing secrets

#### Scenario: Release text from trailers
- **WHEN** two commits since `v1.1.1` carry `Release-Note-de`/`Release-Note-en` and three do not, and `v1.1.2` is pushed
- **THEN** the release text lists the two notes in a German and an English section and nothing else

#### Scenario: No trailers in the range
- **WHEN** no commit since the previous release tag carries a release-note trailer
- **THEN** the run shows a warning and the text lists the commit subjects without task-mark and archive commits

### Requirement: Signed update feeds
For every release and nightly, CI SHALL publish a Sparkle appcast signed with the EdDSA key
from the secret `SPARKLE_ED_PRIVATE_KEY`: the release's `appcast.xml` (reached through
`releases/latest`) and the nightly's `appcast.xml`, each pointing to its DMG with the build
number as version and the release notes in German and English (`xml:lang`), taken from the
commit trailers as for the release text.

#### Scenario: Release published
- **WHEN** the release workflow publishes 1.2.0
- **THEN** `releases/latest/download/appcast.xml` lists 1.2.0 with its DMG, signature and notes in German and English
