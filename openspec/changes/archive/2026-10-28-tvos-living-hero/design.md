# Design

## Context

- Start draws the large entry's backdrop full screen behind the page in `StartBackdrop`
  (tvos-start-scrolling), which alone reads the scroll offset; the entry itself (`Hero`) is a
  focus section with "Abspielen" and "Info".
- Jellyfin's spotlight (`JellyfinSpotlight`, tvos-jellyfin-overview, not merged yet) draws its
  backdrop inside a rounded 560-point card.
- Backdrops: Jellyfin items carry `backdropImageTags` (one tag per backdrop, fetched by index);
  the provider's film and series info carry `backdrop_path` as a list, of which
  `MovieDetails.backdrop` and `SeriesInfo.backdrop` keep only the first.
- Start's scroll measurement (StartScrollingUITests) fails above 40 late frames; the animation
  must not make scrolling stutter.

## Goals / Non-Goals

**Goals:**
- A calm, modern movement while the entry has focus; nothing that distracts while browsing rows.
- No streams, no extra work while scrolling.

**Non-Goals:**
- Video, trailers, sound; the Mac; poster cards.

## Decisions

1. **One `LivingBackdrop` view** taking a list of image URLs, an `active` flag and a size: it
   shows the current image with a `scaleEffect`/`offset` animated by `TimelineView(.animation)`
   only while `active` (a 20 s cycle from scale 1.0 to 1.08 and a pan of 2 % along a direction
   that changes per image), and cross-fades to the next URL every 8 s (`.transition(.opacity)`
   with a 1.2 s ease). Inactive, the `TimelineView` is paused (`.animation(paused:)`), so it
   costs nothing; the image keeps its last transform. Rejected: `withAnimation(.repeatForever)`
   (cannot pause in place, jumps back when focus leaves).

2. **Focus reaches the backdrop without rebuilding Start.** `Hero` reports its focus
   (`.onChange` of a `@FocusState` on its section) into the existing `StartScroll` observable,
   which only `StartBackdrop` reads (tvos-start-scrolling design 1). The Jellyfin spotlight
   holds the flag itself.

3. **All backdrops.** `MovieDetails.backdrops` and `SeriesInfo.backdrops` keep the full
   `backdrop_path` list (`backdrop` stays as the first); `JellyfinStore.backdropURLs(_:)` returns
   one URL per tag (`Images/Backdrop/<index>`). At most 5 per title; images load through
   `ImagePipeline` like now, the next one is requested before its cross-fade.

4. **Reduce Motion** (`accessibilityReduceMotion`): no zoom or pan, cross-fade only.

5. **Entry text** (eyebrow, title, facts) gets `.transition(.opacity.combined(with:
   .offset(y: 12)))` keyed on the entry's id, so a new suggestion or item eases in. The buttons
   keep their identity: giving them a new id with the entry would drop the focus resting on
   "Play" whenever the entry changes underneath it.

6. **The motion's clock runs only while active.** `LivingBackdrop` adds up active time itself
   (time before the current focus span plus the span so far) instead of reading the wall clock,
   so focus leaving and returning continues the zoom where it stopped rather than jumping. The
   cycle runs over the backdrops already loaded: the first loads at once, the others only once
   the entry has focus, so Start does not fetch them for a title nobody looks at.

## Risks / Trade-offs

- [GPU work while the hero has focus] → only one image layer animates, at 30 fps cadence of the
  timeline is enough (`.animation(minimumInterval: 1/30)`); measured with IPTV_FRAMESTATS.
- [Titles with one blurry backdrop look odd zoomed] → the zoom stops at 8 %; images are fetched
  at 1920 px as now.
