# Design

## Context

**The project:**
- One app target "Fernsy" with no Swift packages so far. FFmpeg is embedded by a build-phase
  script.
- The Info.plist is generated (`GENERATE_INFOPLIST_FILE`, plus `Config/Info.plist`), and the
  entitlements are `Config/Fernsy.entitlements` (sandbox, network client, Movies, user-selected
  files).

**The builds:**
- `scripts/build-dmg.sh` builds Release with Developer ID.
- `scripts/build-appstore.sh` archives for the App Store.
- `.github/workflows/release.yml` builds both from tags, and the DMG nightly.
- Versions come from the tag. The build number is the commit count, so it always rises.

**Releases:** releases carry `Fernsy.dmg`; the nightly is a rolling pre-release with
`Fernsy-Nightly.dmg`. Release 1.1.0 has no updater.

**Recordings** only run while Fernsy is open, and the app can live in the menu bar. A relaunch
during a recording would cut it off.

## Goals / Non-Goals

**Goals:**
- DMG users learn about updates and install them with one click, signed and sandbox-safe.
- Nightly builds are available on request.
- Recordings are never cut off by an update.
- The App Store build stays free of any updater.

**Non-Goals:**
- Delta updates.
- Forced updates.
- An updater for the App Store build.
- Its own update implementation.

## Decisions

### 1. Sparkle 2 rather than our own updater

Sparkle 2 covers everything this needs:
- feed parsing;
- EdDSA signature checks;
- download;
- installation by an XPC installer service that works in the sandbox;
- relaunch;
- a localized update window.

It is maintained, MIT-licensed and used by most Mac apps outside the App Store.

Rejected:
- **Our own check against the GitHub Releases API with a "Download" link:** it is simpler,
  but the user installs by hand, there is no signature check, and the sandbox makes it hard
  to replace the app.
- **Homebrew cask:** this reaches only a part of the users, and it is a different channel.

### 2. A second target instead of a runtime switch

"Fernsy Direct" is a copy of the app target:
- **same:** sources, resources, build phases (FFmpeg), product name `Fernsy`, bundle ID;
- **added:** the Sparkle package, `SWIFT_ACTIVE_COMPILATION_CONDITIONS += DIRECT_DISTRIBUTION`,
  `CODE_SIGN_ENTITLEMENTS = Config/Fernsy-Direct.entitlements`, and Sparkle's Info.plist keys
  as `INFOPLIST_KEY_*` build settings.

`build-dmg.sh` builds the scheme "Fernsy Direct". Updater code lives in `#if DIRECT_DISTRIBUTION`.

Rejected:
- **One target that starts Sparkle only in DMG builds:** `Sparkle.framework` and the
  temporary-exception entitlements would still be in the App Store bundle. App Review rejects
  both (guideline 2.4.5).
- **Embedding Sparkle afterwards with a script and loading it with `dlopen`:** fragile, and
  the code would not be type-checked.

New source files must be added to both targets. The project has few targets, and the task
list checks it with a build of both.

### 3. Sandbox setup

`Config/Fernsy-Direct.entitlements` = the app's entitlements plus
`com.apple.security.temporary-exception.mach-lookup.global-name` with
`$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `$(PRODUCT_BUNDLE_IDENTIFIER)-spki`.

Info.plist settings:
- `SUEnableInstallerLauncherService = YES`;
- no downloader service, because the app already has `network.client`;
- `SUPublicEDKey`;
- `SUFeedURL` = the release feed;
- `SUScheduledCheckInterval = 86400`.

Sparkle's XPC services are signed by the build like the app. The task list checks
notarization and `spctl` in CI.

### 4. Feeds as release assets, chosen in the app

The workflow runs Sparkle's `generate_appcast` (from the package's binary distribution, or
the release archive in CI) over the DMG. It signs with `SPARKLE_ED_PRIVATE_KEY` (passed with
`--ed-key-file -` on stdin) and sets the download URL prefix to the release. It takes the
release text as notes. The result is attached as `appcast.xml`:
- to the release: the URL is `…/releases/latest/download/appcast.xml`, stable without bot
  commits;
- to the nightly pre-release: `…/releases/download/nightly/appcast.xml`.

`SPUUpdaterDelegate.feedURLString(for:)` returns the nightly URL when "Nightly-Builds
erhalten" is on (UserDefaults `updates.nightly`), otherwise the release URL.

The setting's default comes from the build. A nightly (version `nightly-…`) registers `true`,
a release `false`, through `UserDefaults.register`. A nightly downloaded by hand thus keeps
following nightlies; otherwise its high build number would wait for the next release. An
explicit choice by the user overrides the default.

Sparkle compares `sparkle:version` = `CFBundleVersion` = the commit count. A release after
nightlies therefore only counts as newer when its commit count is higher, which holds for
tags on main. The display shows `sparkle:shortVersionString`.

Rejected:
- **An appcast on the website** (`website/appcast.xml`): every release would need a bot
  commit to main, which in turn triggers the Pages workflow.
- **One feed with Sparkle channels:** the nightly entries would also have to be in the
  release's feed. Release and nightly are published independently.

### 5. Recordings postpone the installation

`SPUUpdaterDelegate`:
- `updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)` returns `true` when
  `Recorder` has a running recording or one starting within 30 minutes. Fernsy keeps the
  block and calls it as soon as no recording is due; the recorder ticks every 5 s.
- `updaterShouldRelaunchApplication` stays the default.

In addition, Sparkle's "Install on Quit" covers the case where the user quits Fernsy anyway.
The existing "quit during a recording" question still applies.

The update window shows a note through `SPUStandardUserDriverDelegate`. If needed, an alert
before installing says "Das Update wird nach der Aufnahme „…“ installiert."

### 6. Interface

- **Menu:** `CommandGroup(after: .appInfo)` with "Nach Updates suchen …", bound to
  `updater.canCheckForUpdates`.
- **Settings:** a section "Updates" in the Konten tab, only in the DMG build, with:
  - "Automatisch nach Updates suchen" (`automaticallyChecksForUpdates`);
  - "Nightly-Builds erhalten";
  - the last check;
  - "Jetzt suchen".
- Sparkle's own windows are localized (de/en).

### 7. Key

The user runs Sparkle's `generate_keys` once. The private key stays in their keychain, and an
export goes into the secret `SPARKLE_ED_PRIVATE_KEY`. The public key goes into the build
setting `INFOPLIST_KEY_SUPublicEDKey` of the Direct target.

A lost private key means: a new key, and one manual update for all users. The README says to
keep the key safe.

### 8. Findings during implementation

- **Custom Info.plist keys.** `INFOPLIST_KEY_*` build settings only cover Apple's known keys.
  The Direct target therefore has its own `Config/Info-Direct.plist`: the shared keys plus
  `SUFeedURL`, `SUPublicEDKey` (from the build setting `SPARKLE_PUBLIC_ED_KEY`),
  `SUEnableInstallerLauncherService` and `SUScheduledCheckInterval`.
- **Sparkle's helpers stay ad-hoc signed.** Xcode signs `Sparkle.framework`, but not
  `Installer.xpc`, `Downloader.xpc`, `Autoupdate` and `Updater.app`, which notarization
  rejects. `build-dmg.sh` re-signs them inside out with the identity, hardened runtime and
  timestamp, then the framework, then the app with the entitlements it was built with.
- **`generate_appcast` only signs when the keys match.** It writes `sparkle:edSignature` only
  when the app's `SUPublicEDKey` matches the private key, so the workflow fails on an unsigned
  appcast. The private key is the base64 of the 32-byte Ed25519 seed (what
  `generate_keys -x` exports).
- **No key, no updater.** Without `SUPublicEDKey` the app does not start Sparkle (which would
  report errors). Without `SPARKLE_ED_PRIVATE_KEY` the workflow warns and builds without a
  feed, so nightlies keep working until the key is set up.
- **Debug builds share Sparkle's settings with the installed app** (same container). Sparkle
  only starts in Debug with `IPTV_UPDATEFEED`.
- **Strings come from the Direct build.** The updater's texts only exist in the "Fernsy
  Direct" compilation. `xcstringstool sync` has to read that target's `.stringsdata` (its
  folder name contains a space), otherwise the updater's keys are marked stale.
- **No shared scheme.** Xcode generates the schemes "Fernsy" and "Fernsy Direct"
  automatically. A shared scheme for one of them would stop the generation for the other.

## Risks / Trade-offs

- **[Two targets drift apart]** → New files go to both. The task list and CI build both
  variants (the nightly builds Direct, `appstore-test` builds Fernsy).
- **[Sandboxed Sparkle installation is more involved]** → It is tested in CI (notarization,
  `spctl`) and once by hand: install the nightly over an older nightly. That manual test is
  the user's, because Fernsy must not be launched while they use it.
- **[1.1.0 users get no update offer]** → Accepted. The release notes of the first version
  with the updater say so.
- **[Order of archives]** → This change modifies "DMG for direct installation" in the form
  from `website-redesign-and-dmg-release`. That change is archived first.
