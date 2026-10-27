# Proposal

## Why

On Apple TV, Live TV and Programm are two tabs that each keep their own channel source. A
category chosen in Live TV is gone in Programm, which starts on Favoriten and offers only
Favoriten, Zuletzt gesehen, Alle Sender and the pinned categories from a menu; every other
category cannot be shown in the guide at all. In Live TV the source also changes as focus
passes over the category column, so moving through the column swaps the channel list without
a click (a UI test ran into this). The Mac shows the guide as a view of Live TV with the
category chosen once; the Apple TV should work the same way.

## What Changes

- **BREAKING (Apple TV navigation)**: the "Programm" tab goes away. Live TV gets a view switch
  "Liste | Programm" at the top of the screen; both views show the same channel source.
- One source for Live TV: the category column on the left serves both views. In Programm it
  narrows to a slim rail showing the chosen source's name; moving left from the guide's channel
  column opens it again over the grid.
- The source changes only when an entry in the column is clicked, not when focus passes it.
- Every category can be the source of both views: the column's "Alle Kategorien" and its
  tiles open the category in the current view, pinned or not.
- The chosen source and view are kept across launches; the player's zapping follows the
  chosen source, as today.
- Programm keeps its grid, time axis, playing and scheduling from tvos-live.

Out of scope:
- The Mac app (it already works this way).
- Changes to the guide grid itself (time window, cells, colours).
- The Start screen and the channel strip in the player.

## Capabilities

### New Capabilities

### Modified Capabilities
- `apple-tv`: navigation without the Programm tab; Live TV with the view switch and one source
  chosen by click; the program guide as Live TV's second view for any category.

## Impact

- `FernsyTV/Screens/RootScreen.swift` (tabs), `ChannelListScreen.swift` (view switch, column
  in both views, select on click), `GuideScreen.swift` (source from the model, no own menu),
  `AllCategoriesScreen.swift` (opens the category in the current view).
- `FernsyTV/Model/TVModel+Live.swift`: the chosen source and view as model state kept per
  account.
- UI tests: `TabsUITests`, `GuideUITests`, `LiveTVUITests`, `AllCategoriesUITests`, the search
  and recordings tests that open Programm.
- German strings for the switch. The Claude Design screens show Programm as a tab; the user
  agreed to deviate from the design for the switch and the rail (design E).
