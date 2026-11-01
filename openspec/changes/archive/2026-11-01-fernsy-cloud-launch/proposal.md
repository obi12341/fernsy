# Proposal

## Why

Fernsy Cloud (recordings cloud) and the in-app assistant are built, tested and reviewed but hidden
behind `FERNSY_CLOUD` (add-recording-cloud design H). The user confirmed the launch prerequisites
on 2026-11-01: the subscription product in App Store Connect, the CloudKit schema in Production,
the App Store privacy details and review notes. The next release should offer them.

## What Changes

- App Store builds of the Mac, Apple TV and iPhone/iPad apps are built with `FERNSY_CLOUD=YES`
  (`build-appstore.sh`, which also fails when an archive's `FernsyCloud` key is not as expected).
- The Apple TV's `Info-TV.plist` gets the `FernsyCloud` key the Mac and iOS plists already have.
- The production worker `fernsy-cloud` gets the assistant relay and its provider key.
- The website's privacy pages (German, English) describe iCloud sync, Fernsy Cloud and the
  assistant, replacing "no personal data to anyone".
- The DMG stays without Fernsy Cloud (no purchases outside the App Store).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None: the specs already describe Fernsy Cloud and the assistant; this change turns them on.

## Impact

`scripts/build-appstore.sh`, `Config/Info-TV.plist`, `website/datenschutz.html`,
`website/en/privacy.html`, `website/style.css`, `DEVELOPMENT.md`, the production worker.

## Out of scope

Pricing (stays 2.99 €), submitting the release for review (the user does that), the DMG.
