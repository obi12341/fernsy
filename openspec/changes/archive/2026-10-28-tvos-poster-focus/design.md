# Design

## Context

- `PosterCard` and `WideCard` (LibraryComponents.swift) draw artwork via `RemoteImage`
  (`Image(uiImage:)` once loaded, else `ArtPlaceholder`, a gradient) with badges in a `ZStack`.
  The watched badge is `Image(systemName: "checkmark")` in a purple circle; all other badges are
  `Text` (`Tag`, the count circle, the rating).
- Callers wrap them in `Button`/`NavigationLink` with `.buttonStyle(.borderless)`. On tvOS that
  style gives the label's image the system focus effect (lift, scale, parallax sheen); which
  views get it is decided by the system from the label, not by the app.
- Observed by the user: the checkmark grows unnaturally when the poster is focused.

- Confirmed (task 1.1, demo films with artwork, Jellyfin copies without): the effect lands on
  every image in the button separately. The artwork zooms inside its clipped frame (its title
  runs into the rating), the checkmark grows on its own, glossy and cut off; the poster as a
  whole does not lift.

## Goals / Non-Goals

**Goals:**
- One focus effect per card, on the card as a whole; badges stay proportional.
- Keep the look of the system effect (lift and sheen) the user knows from Apple's apps.

**Non-Goals:**
- Redesigning badges; the Mac app.

## Decisions

1. **Confirm first.** A UI test focuses a watched poster with artwork and one without (demo
   server films with and without posters, `IPTV_TESTRESUME` to mark them watched) and takes
   screenshots focused and unfocused. This shows whether the effect lands on the checkmark
   always or only without artwork, before anything is changed.

2. **Name the view that gets the effect.** The poster's artwork-and-badges block (the clipped
   `ZStack`) gets `.hoverEffect(.highlight)`; with an explicit hover effect in the label, the
   borderless style applies its effect to that view instead of searching the label for an
   image. Badges inside it are scaled with it. Rejected: drawing the checkmark as text or a
   shape so it is not an image (works around the symptom, the next image badge would bring it
   back); a custom `ButtonStyle` with `scaleEffect` (loses the system's lift, shadow and sheen,
   and every caller would change).

3. **Fallback if (2) does not change the system's choice:** a `PosterButtonStyle` that applies
   `.hoverEffect(.highlight)` to the whole label, used by all poster and card buttons instead of
   `.borderless`. Decided by the screenshots of task 2.1.

## Risks / Trade-offs

- [The title under the poster must not move with it] → the hover effect goes on the artwork
  block only, the title stays outside, as now.
- [Different behaviour across tvOS versions] → the app targets tvOS 27 only; the UI test pins it.
