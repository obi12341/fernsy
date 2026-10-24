# app-updates Specification

## Purpose
Keeps the directly distributed (DMG) Fernsy up to date: it checks for new versions, offers
and installs them with Sparkle, offers nightly builds on request, and never interrupts
recordings for an update.

## Requirements

### Requirement: Checking for updates
The DMG build SHALL check a signed feed for newer builds once a day when automatic checks are
on (the default, switchable in Settings) and SHALL offer "Nach Updates suchen …" in
the Fernsy menu and in Settings. An update SHALL show its version and release notes and offer
Install, Later and Skip; it is only installed when its EdDSA signature matches the app's key.

#### Scenario: New release available
- **WHEN** release 1.2.0 is published and the DMG build 1.1.x runs with automatic checks on
- **THEN** within a day Fernsy shows the update to 1.2.0 with its release notes

#### Scenario: Manual check, nothing new
- **WHEN** the user chooses "Nach Updates suchen …" and the newest build is installed
- **THEN** Fernsy says that it is up to date

#### Scenario: Tampered download
- **WHEN** the downloaded update's signature does not match the app's public key
- **THEN** Sparkle refuses to install it

### Requirement: Nightly channel
Settings SHALL offer "Nightly-Builds erhalten", off by default in releases and on by default in
nightly builds; the user's own choice is kept. When on, the app SHALL check the nightly feed
instead of the release feed; builds are compared by build number, so a newer release replaces
an older nightly.

#### Scenario: Opting in
- **WHEN** the user turns on nightly builds and a nightly newer than the installed build exists
- **THEN** Fernsy offers that nightly as an update

#### Scenario: Nightly installed by hand
- **WHEN** the user installs the nightly DMG from GitHub and never touched the setting
- **THEN** the setting is on and the next nightly is offered as an update

#### Scenario: Releases stay on releases
- **WHEN** a user runs release 1.1.1 with the setting untouched
- **THEN** only release 1.1.2 is offered, never a nightly

#### Scenario: Opting out
- **WHEN** the user turns nightly builds off while running a nightly
- **THEN** Fernsy offers the next release whose build number is higher than the installed one

### Requirement: Updates do not interrupt recordings
An update SHALL NOT be installed and Fernsy SHALL NOT relaunch while a recording runs or
starts within 30 minutes; the installation waits until the user quits Fernsy or no recording
is due.

#### Scenario: Update during a recording
- **WHEN** the user clicks Install while a recording runs until 22:55
- **THEN** Fernsy says the update is installed after the recording, keeps recording, and installs it after 22:55 or on quit

### Requirement: No updater in the App Store build
The App Store build SHALL contain neither Sparkle nor any update menu, setting or feed.

#### Scenario: App Store version
- **WHEN** the user runs Fernsy from the Mac App Store
- **THEN** there is no "Nach Updates suchen …" and updates come from the App Store
