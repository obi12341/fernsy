# Design

## Context

- The iOS and tvOS versions 1.0 are "Prepare for Submission" in App Store Connect, with builds
  uploaded by CI but empty product pages. The Mac version is in review with its own texts in
  `docs/app-store.md`.
- The sizes and placements come from App Store Connect itself (checked 2 Nov 2026, see the
  proposal's table). Header and search results exist only for the iOS app, carry no text fields,
  and are attached per localization; tvOS offers screenshots and previews only.
- Simulators for every size are installed: iPhone 18 Pro (6.3"), iPhone Duo, iPad Pro 13-inch
  (M5) and Apple TV 4K (3rd generation).
- The UI tests already sign in to the demo server through launch environment (`launchDemo` in
  `FernsyiOSUITests` and `FernsyTVUITests/UITestSupport.swift`) and force English with
  `-AppleLanguages`; the demo server answers in the app's language (demo-server spec).
- There is no ffmpeg command on the Mac (only the LGPL libraries inside the app). The website
  images are rendered from HTML with headless Chrome.

## Goals / Non-Goals

**Goals:** every upload slot the iOS and tvOS product pages need, in German and English, made by
scripts from the real apps, so a redesign only means running them again.

**Non-Goals:** uploading through the API, custom product pages, header videos, Mac media.

## Decisions

### 1. Screenshots by debug switches and simctl
`scripts/store-media.sh shots` installs Fernsy Dev (Debug) in each simulator, sets the status bar
(`simctl status_bar override`: 9:41, full battery, Wi-Fi) and launches the app once per scene with
the demo account, `-AppleLanguages (de|en)` and the debug switches that open the scene
(`IPTV_TAB`, `IPTV_LIVEVIEW`, `IPTV_DETAIL` or `IPTV_OPEN`, `IPTV_AUTOPLAY` with `IPTV_PLAYERMODE`
and `IPTV_KEEPCONTROLS`, `IPTV_SEARCH`, on Apple TV `IPTV_TESTRECORD`). After a fixed wait it
takes `simctl io screenshot` (native pixels, the sizes App Store Connect wants), removes the alpha
channel (`scripts/store-flatten.swift`, CoreGraphics) and checks size and both languages.
The Apple TV app gets the three switches iOS already had (`IPTV_LIVEVIEW`, `IPTV_KEEPCONTROLS`,
`IPTV_SEARCH`), debug builds only.
This replaces the planned screenshot UI test: the switches already exist for exactly this
(DEVELOPMENT.md: "the simulator takes no touch input from scripts, so debug switches open
screens"), a launch per scene is independent of focus and gesture timing, and no test build is
needed. UI tests stay for the previews (decision 2), which need movement.
Rejected: a screenshot UI test (slower, and its taps and focus moves are what the switches avoid);
hand-made screenshots (not repeatable); design mockups as for the website (App Review wants the
app in use, and the mockups lag behind the app); fastlane `snapshot` (another Ruby toolchain for
what xcodebuild and simctl already do).

### 2. App previews recorded with simctl, finished with AVFoundation
`scripts/store-media.sh previews` starts `simctl io recordVideo` and runs `StorePreviewUITests`, which plays a fixed sequence with pauses (open live TV, zap, open the guide, open a
film and play it). A Swift script (`scripts/store-preview.swift`) trims the recording to the
test's own start and end marks, scales and crops it to the preview size, sets 30 fps and adds a
silent stereo track (App Store Connect rejects previews without audio).
Rejected: an ffmpeg command line (not installed, and the project bundles only libraries);
recording a real device with QuickTime (manual, needs the user and a provider).

### 3. Header and search images from HTML
`scripts/store-art/` holds one HTML page per placement with the brand background, the line of
text and two or three of the screenshots from decision 1 placed in device-less frames.
`render.sh` renders it with headless Chrome at the exact pixel size per language into
`dist/store/ios/<language>/header.png` and `search.png` (no alpha). Text and screens stay in the
middle 60 % so the header's and the search card's crops both keep them.
Rejected: one universal 5244 × 2950 image for both placements (the 21:9 and 3:2 crops cut text
differently, so two images are safer); generated or stock art (the assets must show the app and
stay 4+).

### 4. Texts per platform in `docs/app-store.md`
The file gets the sections "iPhone und iPad" and "Apple TV" (German and English) with promotional
text (170), description (4000), keywords (100) and what's new (4000), and a section
"Kopfzeile und Suche" with the image lines (aim 40 characters). Each platform's description names
only that platform's features: no menu bar or PiP window on Apple TV, Top Shelf only there. Name
and subtitle stay shared. `check-store-texts.py` keeps working, since it reads every
`### Title (limit)` heading.
Rejected: one shared description for all platforms (each describes features the others lack).

### 5. Upload stays manual
The user uploads screenshots, previews and images in App Store Connect and pastes the texts, as
for the Mac. A script lists what goes where.
Rejected: uploading through the App Store Connect API now (a further tool and key handling for a
once-per-redesign step); it can follow as its own change.

## Risks / Trade-offs

- [iPhone Duo screenshots] → The Duo simulator starts folded: the app shows on the cover display,
  rendered sideways there, and the inner display stays black. Unfolding needs the Simulator's menu
  (input on the user's Mac), and powering the displays with `simctl io screenConfig` crashed
  SpringBoard. So the user unfolds the simulator once; the script shoots the inner display and
  stops with that hint when it gets a black image.
- [Live picture] → A demo channel shows wherever its loop stands at that moment, often the film's
  title cards. The script picks, at shot time, one of the first twelve channels that is in the
  middle of the film (the loop and the 41 s offset per channel are in `demo-server/worker.js`).
- [Waits in the preview walk] → Every XCUITest tap or remote press waits for the app to settle
  (about three seconds on iOS) and every `waitForExistence` costs about a second, which the
  recording shows. The walks use direct taps and few pauses; the script warns when a walk is
  outside 15–30 s instead of cutting it silently.
- [App Review of the images] → Header and search images are reviewed; keeping to app screens,
  demo content and no prices avoids the usual rejections.
- [Redesigns] → Screens change; the shots are cheap to take again, and the scene list in the test
  is the only place to adjust.
