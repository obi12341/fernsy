# Proposal

## Why

Since `release-from-tags`, Fernsy is also distributed as a notarized DMG through GitHub
releases and the website. DMG users never learn about new versions: they would have to check
the website themselves. The App Store updates its build; the DMG build needs its own
mechanism.

There is no need to write one. **Sparkle 2** (MIT, Swift Package) is the standard for Mac
apps outside the App Store. It handles feed, download, EdDSA signature check, installation
and relaunch, and it supports sandboxed apps through its XPC services. Its user interface
comes in German and English.

## What Changes

- **Sparkle 2 only in the DMG build.** A second target, "Fernsy Direct", uses the same
  sources plus the Sparkle package and the compile flag `DIRECT_DISTRIBUTION`. It has its
  own entitlements, which add Sparkle's sandbox mach-lookup exceptions. The App Store target
  stays free of Sparkle, because Apple rejects apps with their own update mechanism.
  `build-dmg.sh` and CI build "Fernsy Direct"; `build-appstore.sh` builds "Fernsy".
- **Updates in the app (DMG build only):**
  - the menu item "Nach Updates suchen …" in the Fernsy menu;
  - a daily automatic check, with Sparkle's consent prompt at the second launch;
  - Sparkle's update window with release notes, Install, Later and Skip;
  - a "Updates" section in Settings: check automatically (on/off), receive nightly builds
    (off), last check, "Jetzt suchen".
- **Recordings are protected.** An update never installs or relaunches while a recording
  runs or starts within the next 30 minutes. Sparkle postpones the relaunch and installs when
  the user quits, or after the recordings.
- **Feeds from CI, without bot commits.** The release workflow creates and signs a Sparkle
  appcast with `generate_appcast` and the EdDSA key from a secret, and attaches it to the
  release:
  - stable: `releases/latest/download/appcast.xml`;
  - nightly: `releases/download/nightly/appcast.xml`.

  The app picks the feed by its setting. Sparkle compares the build number (commit count),
  which always rises; the version text is only displayed.
- **The EdDSA public key in the Info.plist** of the Direct target (`SUPublicEDKey`), and the
  private key as the repository secret `SPARKLE_ED_PRIVATE_KEY`.

Out of scope:
- updates for the App Store build;
- delta updates;
- forced updates;
- a fallback path for 1.1.0 (it has no updater; its users install the next version once by
  hand).

## Capabilities

### New Capabilities
- `app-updates`: checking for, offering and installing updates of the DMG build, the stable
  and nightly feeds, and protecting recordings during updates.

### Modified Capabilities
- `distribution`:
  - "DMG for direct installation" builds the "Fernsy Direct" variant with the updater;
  - the App Store build contains no updater;
  - the release workflow publishes signed appcasts.

## Impact

- `Fernsy.xcodeproj`:
  - a new target "Fernsy Direct" (same sources and resources, product name `Fernsy`, bundle
    ID `de.mobilistics.fernsy`), with the Swift package Sparkle 2 and `DIRECT_DISTRIBUTION`;
  - `Config/Fernsy-Direct.entitlements`;
  - Info.plist keys `SUFeedURL`, `SUPublicEDKey`, `SUEnableInstallerLauncherService` and
    `SUScheduledCheckInterval` via build settings.
- New `Fernsy/App/Updater.swift` (behind `#if DIRECT_DISTRIBUTION`): the
  `SPUStandardUpdaterController`, the feed choice, and the recording protection through
  `SPUUpdaterDelegate`.
- Menu (`FernsyApp.swift`), Settings (`LoginView.swift`, a section or tab).
- `scripts/build-dmg.sh` (scheme/target), `.github/workflows/release.yml` (appcast steps,
  secret), README, `Localizable.xcstrings`.
- The user creates the EdDSA key pair once with Sparkle's `generate_keys` and sets the
  secret.
