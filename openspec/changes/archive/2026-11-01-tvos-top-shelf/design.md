# Design

## Context

See proposal.md for the motivation. Today:
- The Top Shelf images are assets in `FernsyTV/Assets.xcassets/TVAppIcon.brandassets` (and
  `TVAppIcon-Dev`), rendered by `scripts/make-tv-icons.swift` from the Mac icon.
- Start's rows come from `StartBuilder` through `TVModel+Start.swift`: `continueWatching`,
  `startChannels` (favorites, else recently watched, without hidden channels) and
  `recordingEntries`. The Apple TV library already drops adult categories and items on load
  (`TVModel+Library.swift`).
- Jellyfin images are plain URLs with a tag and need no token (`JellyfinClient.imageURL`). IPTV
  posters and logos are the provider's URLs, often plain HTTP.
- The debug MCP tool `play_item` (`FernsyTV/Debug/TVTools.swift`) already maps ids like
  `movie:500`, `episode:<series>:<episode>`, `jellyfin:<id>` to `TVModel.play`.
- The Apple TV app has no URL scheme and no App Group.

tvOS API: a Top Shelf extension's `TVTopShelfContentProvider.loadTopShelfContent()` returns
`TVTopShelfSectionedContent` (rows of `TVTopShelfSectionedItem` with image shape, title,
`playbackProgress`, `playAction` and `displayAction` as URLs) or `nil` for the static image. The
app calls `TVTopShelfContentProvider.topShelfContentDidChange()` after new data.

## Goals / Non-Goals

**Goals:**
- The Top Shelf shows exactly what Start shows, with no second set of rules.
- The extension stays small: it reads a file and builds items. No network login, no catalog.

**Non-Goals:**
- Showing content the app has not loaded yet (the extension never talks to the provider).

## Decisions

### 1. The app writes a snapshot; the extension only reads it

When Start's rows change (the same inputs that refresh Start: positions, Jellyfin's lists,
favorites, recordings), `TVModel` writes `topshelf.json` into the App Group container. The write
is debounced by 2 s. The file holds sections of items: id, title, subtitle, image file name,
shape, progress, play and display URL. Then the app calls `topShelfContentDidChange()`. The
extension decodes it with a small `Codable` type from FernsyCore (`TopShelfSnapshot`, shared
by both targets) and returns sections, or `nil` when the file is missing or empty.

Rejected: the extension loading the catalog or Jellyfin itself. It would need the credentials
(keychain sharing), repeat the filtering rules, and run network requests in a process tvOS
limits strictly.

### 2. Images are copied into the shared container

For every item the app saves a JPEG (backdrop 16:9, logo square) into
`<group>/TopShelf/<hash>.jpg` from its image cache, scaled to the Top Shelf size, and the
snapshot references file URLs. Files no longer referenced are deleted after each write.

Rejected: handing tvOS the remote URLs. Many IPTV logos are plain HTTP, Jellyfin often sits on
a LAN address, and the Top Shelf would show empty tiles whenever the server is asleep.

The extension has to give tvOS URLs it can read. Whether the Top Shelf accepts `file://` URLs
from the App Group is checked first, in a spike on the real Apple TV (task 1.1). If it does not,
the extension serves the images through its own data URLs, which needs a new decision.

### 3. Deep links through a `fernsy://` scheme

`fernsy://play?item=<id>` plays, `fernsy://open?item=<id>` opens the item's page. The ids are
the ones `play_item` already uses, plus `live:<id>` and `recording:<uuid>`. The parsing moves
from `TVTools` into `TVModel` (`func handle(url:)` / `func play(itemId:)`), so the debug tool
and the URL handling share it. The URL is handled after sign-in has finished: it waits, as
`IPTV_AUTOPLAY` does, until the catalog is there.

The scheme has to be declared in `Config/Info-TV.plist` (`CFBundleURLTypes`). That file holds
the user's own uncommitted change, so this edit happens only after the user commits it or
agrees (task 2.1). There is no build-setting way to declare URL types.

### 4. Rows and shapes

| Row | Shape | Title | Subtitle | Action |
|---|---|---|---|---|
| Continue Watching | `.hdtv` (16:9 backdrop, poster fallback) | series name or title | the entry's detail ("S1 E2 · 20 min left") | play |
| Favorite channels / Recently watched | `.square` (logo on the brand color) | channel name | show on now | play |
| Recordings | `.hdtv` | title | channel · date | play |

At most 10 items per row, in Start's order. Row titles are localized in the extension (English
and German) and follow the system language.

### 5. Separate App Groups for release and dev

`group.de.mobilistics.fernsy` and `group.de.mobilistics.fernsy.dev` (from
`$(PRODUCT_BUNDLE_IDENTIFIER)`), so the dev build next to the release app never shows the other
one's content. This matches the dev build's own container (dev-build isolation).

### 6. The static image is drawn, not exported from a design tool

`scripts/make-tv-icons.swift` draws the new Top Shelf images in code from the icon's motif:
- the sunset gradient and layered hills across the full width;
- the sun placed at the golden ratio;
- a few stars;
- the small TV outline and "Fernsy" set at the left third.

It renders 1920×720 and 2320×720 at @1x and @2x, plus the dev variant with the band. Drawing in
code keeps the images reproducible when the icon changes, like the app icon layers today.

Rejected: a photo or screenshot collage of channels. It would show third-party logos and
content in an App Store asset.

### 7. A new target added by hand in the project file

The project uses synchronized folders (`PBXFileSystemSynchronizedRootGroup`). The extension
gets a folder `FernsyTopShelf/` and a native target with its own Info.plist, entitlements, and
an "Embed Foundation Extensions" phase in the Apple TV target. The pbxproj edit is checked by
building the TV scheme in Debug and Release and by `xcodebuild -list`.

## Risks / Trade-offs

- [The Top Shelf caches aggressively] → `topShelfContentDidChange()` after every write. The
  user check covers that a new position shows up after returning to the Home Screen.
- [File URLs from the App Group not accepted] → Spike first (task 1.1); the rest of the plan
  waits for it.
- [Personal content on the Home Screen] → It is what Start shows, already without hidden and
  adult items. Signing out deletes the snapshot and images.
- [The simulator's Home Screen] → The tvOS simulator shows Top Shelf extensions. The UI test
  checks the snapshot file and the URL handling. The look is checked on the simulator by
  screenshot and on the real Apple TV with the user.

## Migration Plan

New target and assets; nothing to migrate. Without the extension, tvOS falls back to the static
image, so a rollback is removing the extension from the build.

## Open Questions

- The exact look of the static image is decided on rendered drafts: two or three variants
  rendered by the script and shown to the user before the final pick (task 4.2). This does not
  change the plan or the tasks.

## As built

- Static image (task 4.2): the user chose "sunset" from the three drafts (sunset, dusk,
  twilight). In the drafts the TV and "Fernsy" sat at the left third and were cut off at the
  left edge on the TV: tvOS crops the sides of the top shelf image. The TV and the name are now
  centred across (`ShelfTitle` in `scripts/make-tv-icons.swift`), and the sun moved from 62 % to
  75 % of the width so the name does not sit in its glow.
- Actions: a click (`displayAction`) and the Play button (`playAction`) both play. The first
  plan let a click open the item's page; the user chose playing, as a click on Start's Continue
  Watching resumes. `fernsy://open` stays for links that should open a page.
- `TVTopShelfSectionedItem` has no subtitle: the subtitle is joined to the title
  ("Title · 20 min left").
- URL scheme: `fernsy` in release builds and `fernsy-dev` in debug builds (build setting
  `FERNSY_URL_SCHEME` in the Apple TV target, `CFBundleURLTypes` in `Config/Info-TV.plist`), so a
  tile written by the dev build next to the release app opens the dev build. `TopShelfLink.scheme`
  reads the app's own scheme from its Info.plist.
- Device builds: the old recipe passed `CODE_SIGN_ENTITLEMENTS=build/tv-device/release.entitlements`
  on the command line for CloudKit Production. A command-line setting applies to every target,
  so the extension got the app's entitlements and the App Group `group.de.mobilistics.fernsy.topshelf`
  (from its own bundle id) instead of the app's. Device builds now build without that override and
  add `com.apple.developer.icloud-container-environment = Production` when re-signing the app only.
- New targets and capabilities need an Apple account in Xcode (Settings › Accounts) for
  `-allowProvisioningUpdates` to create profiles; without one, xcodebuild reports "No Accounts".
- Pitfall: the target first had the product type `com.apple.product-type.tv-app-extension`, whose
  entry point `_TVExtensionMain` (an older tvOS extension kind) returns 3 at once for a Top Shelf
  content provider. tvOS started the extension, it ended after about 0.2 s ("exited due to
  exit(3)"), and HeadBoard showed the static image. Xcode's Top Shelf template uses
  `com.apple.product-type.app-extension` (entry `_NSExtensionMain`), which works. Found by
  attaching lldb to the extension in the simulator (`process attach --name FernsyTopShelf
  --waitfor`, break on `exit`).
- tvOS lets apps write only to caches, also in a shared container: the snapshot and its images
  live in `Library/Caches` of the App Group container (`TopShelfSnapshot.directory`). The
  simulator does not enforce this.

