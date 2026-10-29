# Proposal

## Why

On Apple TV, Down from the last card of a row with four cards skips a following row with only
three cards and lands on the card straight below in the row after it. tvOS moves focus to the
nearest focusable item in the pressed direction; the short row has nothing directly below the
fourth card, so the next row's card wins. Users lose their place and miss a whole row.

## What Changes

- Up and Down on card rows move exactly one row. When the next row has no card under the
  focused one, focus goes to the nearest card of that row (its last card when the row is
  shorter).
- Applies to every horizontal card row on Apple TV: Start, Jellyfin's Übersicht, the film,
  series and search pages that show rows.
- A UI test on Start against the demo server covers a four-card row above a three-card row.

Out of scope:
- Poster grids (Filme, Serien, Jellyfin's Filme/Serien, search results): they are one grid per
  screen, where the focus engine already moves line by line.
- The program guide, the channel list and the player's channel strip.
- iPhone, iPad and Mac.

## Capabilities

### New Capabilities

### Modified Capabilities
- `apple-tv`: Navigation on Apple TV gains row-by-row Up and Down on card rows.

## Impact

- `FernsyTV/Screens/LibraryComponents.swift` (`CardRow`, used by all rows), possibly the rows'
  titles on Start.
- A new test in `FernsyTVUITests`; maybe a DEBUG switch to shape row lengths on Start.
