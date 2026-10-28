# Design

## Context

- Apple TV: `StartScreen` builds its rows from `TVModel.startRows()`, `continueWatching`,
  `recentlyAdded`, `tonight(on:)` and the live source (FernsyTV/Model/TVModel+Start.swift,
  TVModel+Library.swift). The rules are in the app target, typed on `LibraryEntry` (also
  FernsyTV). Building is kept off the redraw path (tvos-start-scrolling): rows are rebuilt when
  their inputs change.
- `JellyfinOverview` (rows, spotlight pick, tiles) is already in FernsyCore with unit tests; the
  Apple TV page (`JellyfinOverviewPage`, `JellyfinBrowseScreen`) is FernsyTV UI.
- Mac: `LibrarySection` has no Start; the app opens on `.live`. `.jellyfinHome` shows
  `JellyfinHomeView` with four `JellyfinCarousel` rows that page with buttons. The Mac model
  (`AppModel`) has the same inputs as `TVModel`: catalog, `ResumeStore`, favorites and recent
  channels, guide, recorder, `JellyfinStore`.
- Package graph: FernsyPlayer depends on FernsyCore, so FernsyCore cannot name `Recording`.
- Mac checks run in "Fernsy Dev" (`scripts/dev-run.sh`, demo server) with window screenshots;
  pointer input cannot be injected (user rule), so hover needs a debug switch.

## Goals / Non-Goals

**Goals:**
- The same rows, in the same order, from the same rules on Mac and Apple TV.
- Mac-native pages: pointer, click, context menus, the player window, paging buttons.

**Non-Goals:**
- Sharing SwiftUI views between the apps (focus engine vs. pointer, sizes, navigation differ).
- Changing the Apple TV pages' behavior.

## Decisions

1. **Start's rules move to FernsyCore as `StartBuilder`.** A pure function from a snapshot of
   inputs (films, series, categories, Jellyfin lists, resume positions, recordings as plain
   values, channels with favorite/recent state, guide entries, now) to `StartRows`, with
   `LibraryEntry` moved along. Recordings enter as `StartRecording` (id, title, status, resume
   key); the entry's target carries the recording id and each app resolves it. Both apps call
   the builder where Apple TV calls `startRows()` today. Rejected: copying the rules into the
   Mac (two rule sets drift; the user expects the same rows); placing the builder in
   FernsyPlayer (UI rules in the player package, and its tests need FFmpeg).

2. **`LibrarySection.start`, first and default.** It sits above the groups (not inside IPTV, as
   it mixes both sources), is the initial selection, and like Jellyfin Home has no category
   column. It shows whenever any account exists. `IPTV_SECTION=start|jellyfinHome` (existing
   debug switch) opens a section directly for checks.

3. **Mac layout.** A vertical `ScrollView` in the detail column: the large entry as a banner
   (backdrop across the column's width, about 420 pt high, text and buttons bottom-left over a
   gradient), then rows as paging carousels generalised from `JellyfinCarousel` (it takes
   `JFItem` today; it becomes generic over the card). Cards reuse the Mac's poster and wide-card
   styles (`JellyfinPoster`, the landscape card) so Start looks like the rest of the Mac app.

4. **Clicks follow the Mac.** Continue Watching, Next Up and live cards play in the player
   window (`AppModel.play…`); posters open the film or series page in the detail stack; a later
   show in Heute Abend opens the Mac's recording question; context menus as on the Jellyfin rows
   (mark watched, favorite, open series).

5. **Mac `LivingBackdrop`.** The Apple TV view's logic (active-time clock, cross-fade over loaded
   backdrops, Reduce Motion) is ported to AppKit-backed SwiftUI with `NSImage` and the Mac's
   `ImagePipeline`; `active` is `onHover` of the large entry. `IPTV_TESTHOVER=1` (debug) keeps it
   active for screenshots, since pointer input cannot be injected. Rejected: a shared view in a
   package (UIImage vs. NSImage pipelines; the view is under 100 lines).

6. **Übersicht.** `.jellyfinHome` keeps its id (stored selections and the debug switch stay
   valid) but is titled "Overview" / "Übersicht" and shows `JellyfinOverview`'s rows as
   carousels, its spotlight as a banner like Start's large entry, and tiles that push a
   `JellyfinBrowseView` grid with the sort picker. "Next Up" leaves this page (it is on Start).

7. **Rebuilding.** As on Apple TV, the Mac pages keep built rows in state and rebuild on a key of
   their inputs (counts, resume changes, guide loads), never in `body`.

## Risks / Trade-offs

- [Moving the rules could change Apple TV's rows] → the builder gets unit tests from the current
  behavior first; Apple TV's Start and overview UI tests must stay green.
- [The Mac window can be narrow] → the banner text scales down and rows show fewer cards per page;
  checked at the window's minimum size.
- [Opening on Start loads more images at launch than Live TV] → the image pipeline's caches as on
  Apple TV; rows are lazy.
- [Users used to opening on Live TV] → the sidebar keeps Live TV one click away; recorded as the
  user's choice (2026-10-28).
