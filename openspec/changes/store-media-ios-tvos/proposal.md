# Proposal

## Why

The iPhone/iPad and Apple TV versions are uploaded by CI (`appstore-tvos-ios`), but their product
pages in App Store Connect are empty: no screenshots, no app previews, no texts of their own. Since
5 October 2026, App Store Connect also offers a product page header and a search results asset
(image or video, per localization, shown on iOS 27 and iPadOS 27). Without them the App Store falls
back to the screenshots. Everything has to exist in German and English before the first iOS and
tvOS submission and the public beta.

## What Changes

App Store Connect (checked on 2 Nov 2026) asks per version and localization for:

| Platform | Screenshots (up to 10) | App previews (up to 3) | Header / search results |
|---|---|---|---|
| iPhone with Dynamic Island (6.1"/6.3") | 1206 × 2622 or 2622 × 1206 | 886 × 1920 or 1920 × 886 | header 3840 × 1646 (21:9), search 3840 × 2560 (3:2) |
| iPhone Duo (new foldable) | 2007 × 2853 or 2853 × 2007 | 886 × 1920 or 1920 × 886 | (same, per localization) |
| iPad 13" | 2064 × 2752 or 2752 × 2064 | 1200 × 1600 or 1600 × 1200 | (same, per localization) |
| Apple TV | 3840 × 2160 | 1920 × 1080 | not offered |

Header and search results have no text fields of their own: their text is part of the image.
Promotional text, description, keywords and what's new are per platform and still empty for iOS
and tvOS.

- **Screenshots** for iPhone, iPhone Duo, iPad 13" and Apple TV, in German and English, taken
  from the real apps in the simulator with the demo server's fictional content. A UI test per
  platform drives the scenes, and a script collects the images at the sizes above into
  `dist/store/`, so they can be taken again after every redesign.
- **App previews** (15–30 s videos) for iPhone, iPad and Apple TV per language, recorded from the
  simulator during a scripted UI test run and cut to the sizes above.
- **Header and search results images** for the iOS app (iPhone and iPad share them): a 21:9
  header and a 3:2 search image per language, composed from the app's own screenshots and one
  short line of text. They are rendered from an HTML template with headless Chrome, as the
  website images are.
- **Store texts for iOS and tvOS**: `docs/app-store.md` gets iPhone/iPad and Apple TV sections
  (promotional text, description, keywords, what's new) next to the Mac ones, plus the lines used
  in the header and search images. `scripts/check-store-texts.py` checks their limits.

Out of scope:
- Uploading or submitting through the App Store Connect API (fastlane `deliver`, API upload).
  The user uploads the media in App Store Connect by hand, as for the Mac.
- Custom product pages and product page optimization (A/B tests).
- New Mac screenshots, and App Store media for Fernsy Cloud (the in-app purchase's own image).
- Header and search videos. They start as still images; a video can follow.
- Apple Watch (Fernsy has no watch app) and screenshots for further iPhone sizes: App Store
  Connect scales the 6.3" set down.

## Capabilities

### New Capabilities

- `store-media`: App Store screenshots, app previews and header/search assets for iPhone, iPad
  and Apple TV, and how they are produced from the apps with demo content.

### Modified Capabilities

- `distribution`: "Store texts within limits" covers the texts per platform (Mac, iPhone/iPad,
  Apple TV) and the header and search texts.

## Impact

- `FernsyiOSUITests/`, `FernsyTVUITests/`: a screenshot test per platform (`StoreShotsUITests`),
  run only on demand (not part of the regular UI test runs).
- `scripts/store-media.sh` (new): runs the shot tests per device and language, extracts the images
  from the `.xcresult`, records the previews (`simctl io recordVideo`) and cuts them.
- `scripts/store-art/` (new): HTML template and render script for header and search images.
- `docs/app-store.md` (local, git-ignored) and `scripts/check-store-texts.py`.
- DEVELOPMENT.md. App Store Connect (user): uploading the media and texts.
