# Proposal

## Why

On Apple TV, a watched film or series shows a checkmark in the poster's top right corner. When
the poster gets focus, the checkmark grows on its own, out of proportion with the poster. The
posters are `.borderless` buttons; tvOS applies that style's focus effect (lift, scale, sheen)
to an image in the button's label. The checkmark is the only badge drawn as an image
(`Image(systemName: "checkmark")`; "Neu", the episode count and the rating are text), so the
effect can land on it, at the latest when the poster has no artwork and shows the gradient
placeholder.

## What Changes

- The focus effect applies to the whole poster (artwork or placeholder with all its badges),
  so the badges grow and move with the poster at their proportions.
- The checkmark badge looks as before; it is no longer a separate target for the effect.
- The same for wide cards (Continue Watching, Next Up) if their badges show the effect.

No change to which badges show. Out of scope: the Mac app (no focus effect there).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: new requirement that a focused poster grows as one, badges included.

## Impact

- `FernsyTV/Screens/LibraryComponents.swift` (PosterCard, WideCard), possibly a shared poster
  button style; callers in StartScreen, DetailScreens, JellyfinSearchScreens, the grids.
- UI test with screenshots of a focused watched poster, with and without artwork.
