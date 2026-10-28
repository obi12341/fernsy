# Design

## Context

- `JellyfinScreen`: a fixed header (title, state, view switcher in a `focusSection`) above a
  `ScrollView` with `.scrollClipDisabled()`, all inside `.padding(.horizontal, 90)`. Scrolled
  content is drawn above the scroll view's top, over the header; `LazyVGrid` removes rows once
  they leave the scroll view's bounds, which is below the header, visibly.
- `LibraryGridScreen` (IPTV Films/Series) has the header inside the `ScrollView` and no fixed
  part above it; it does not show the overlap.
- `CardRow`: `ScrollView(.horizontal)` + `LazyHStack` + `.scrollClipDisabled()`, placed inside
  pages padded 90 points: cards scrolled left of the margin are drawn in the margin and removed
  there by the lazy stack.
- `.scrollClipDisabled()` exists so a focused card can scale (1.05–1.1) and show its shadow
  without being cut.

## Goals / Non-Goals

**Goals:**
- Nothing scrolls over the Jellyfin header; posters come and go at the screen edges.
- Focused posters still grow and cast their shadow uncut.

**Non-Goals:**
- Other screens with the same pattern (Recordings, All Categories, channel strip) unless the
  screenshots show the effect there; a fixed (pinned) header on the Jellyfin tab.

## Decisions

1. **The Jellyfin header scrolls with the content**, as on the IPTV grids: title, state and view
   switcher become the first part of the `ScrollView`, still their own `focusSection`, so Up from
   the first row reaches the switcher. Rejected: keeping the header fixed and clipping the
   scroll view below it, which cuts focused posters at the top and needs a fade mask to look
   intended; the tvOS pattern (and the app's own Films tab) is a header that scrolls away.

2. **Scroll views span the screen; the margin moves inside.** The outer `.padding(.horizontal, 90)`
   is replaced by `.contentMargins(.horizontal, 90, for: .scrollContent)` on the scroll views,
   so their bounds are the screen and lazily removed items are off-screen. Vertical scroll
   views keep `.scrollClipDisabled()` only where a fixed element above them does not exist.

3. **`CardRow` bleeds to the screen edges.** It takes the page margin as a parameter
   (default 90), applies `.padding(.horizontal, -margin)` to itself and
   `.contentMargins(.horizontal, margin, for: .scrollContent)` inside, so its first card stays
   aligned with the page while cards scroll out at the screen edge. Callers do not change their
   own padding. Rejected: changing every page's padding (many screens, easy to miss one).

4. **Checked with screenshots.** A UI test scrolls the Jellyfin Filme view down and a row on
   Overview sideways (local test Jellyfin) and takes screenshots mid-scroll; the edges are
   checked by eye before and after. Start's rows are covered by StartUITests' screenshots.

## Risks / Trade-offs

- [Focus behaviour when the header scrolls] → `focusSection` stays on the header; the existing
  Jellyfin UI tests (switching views, Up from the grid) cover it.
- [The negative padding of CardRow misaligns a row on a page with a different margin] → the
  margin is a parameter; detail pages pass their own.
