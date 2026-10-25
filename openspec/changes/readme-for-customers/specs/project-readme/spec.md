# Spec Delta

## Purpose
The repository's README is a product page for people who discover Fernsy on GitHub; developer
and agent documentation lives in a separate file.

## ADDED Requirements

### Requirement: README presents the product
`README.md` SHALL be written for prospective users, in English, and SHALL contain, in this
order: the app icon, name and a one-line pitch; download and availability (the newest
release's `Fernsy.dmg`, the App Store note as on the website, system requirements); the main
features with images from the website; and the notice that Fernsy contains no channels or
content and needs an Xtream Codes account. It SHALL link to the website in both languages.

#### Scenario: Visitor opens the repository
- **WHEN** someone opens github.com/obi12341/fernsy
- **THEN** the README shows what Fernsy does, how it looks and where to download it before any
  build or developer instructions

#### Scenario: Images render on GitHub
- **WHEN** the README is rendered on GitHub
- **THEN** every image it references exists in the repository and is shown

### Requirement: Claims match the app and the website
Every feature, requirement and availability statement in the README SHALL be true for the
current release and SHALL NOT contradict the website (for example, the App Store state).

#### Scenario: App Store availability
- **WHEN** the website says Fernsy is coming soon to the Mac App Store
- **THEN** the README says the same and does not link to a store page

### Requirement: Contributing section last
The README SHALL end with a short contributing section: the GPLv3 license with the separately
licensed LGPL FFmpeg, the condition that pull requests need a contributor license agreement,
the build in a few commands, and a link to the developer documentation. No developer content
SHALL appear above it.

#### Scenario: Developer looks for build steps
- **WHEN** a developer scrolls to the end of the README
- **THEN** they find the contribution terms and a link to `DEVELOPMENT.md`

### Requirement: Developer documentation in DEVELOPMENT.md
Build, release, update-signing, demo-server and debug-switch documentation SHALL live in
`DEVELOPMENT.md`, and references from the agent notes and the release workflow SHALL point
there instead of the README.

#### Scenario: Release workflow reports a missing secret
- **WHEN** the release workflow fails because a repository secret is missing
- **THEN** its error message names `DEVELOPMENT.md` as the place with the setup steps
