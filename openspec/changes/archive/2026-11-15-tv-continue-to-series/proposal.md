# Proposal

## Why

On the Apple TV it is hard to get from what you are watching to its series. "Weiterschauen" and
"Nächste Folge" play an episode on click, and Back from the player returns to Start or Übersicht,
not to the series. A long press offers "Details" only on Start's "Weiterschauen" and only for IPTV
titles: a Jellyfin episode gets no menu, and "Nächste Folge" and the rows on Jellyfin's Übersicht
have none at all. The Mac already offers "Open Series" in these rows' context menus.

## What Changes

- A long press on a card in "Weiterschauen" or "Nächste Folge", on Start and on Jellyfin's
  Übersicht, opens a menu: "Fortsetzen" or "Abspielen", "Von Anfang an" (only with progress),
  "Zur Serie" for an episode (IPTV and Jellyfin), "Details" for a film. Recordings get play and
  play from start only.
- An episode started from these rows or from Start's large entry opens its series page beneath
  the player: Back from the player lands on the series page, and Back from there returns to
  Start or Übersicht.
- Clicking a card stays as it is: it plays from where the user stopped.

Out of scope:
- The Mac (it has "Open Series" in its context menus already) and iPhone/iPad.
- Other places that start an episode: the series page itself (Back already lands there), search,
  the Top Shelf, the assistant.
- Films: Back from a film still returns to where it was started.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `apple-tv`: adds "Card menu in Weiterschauen and Nächste Folge on Apple TV" and "Back from an
  episode to its series on Apple TV".

## Impact

- `FernsyTV/Screens/StartScreen.swift` (rows' menus, play with the series page beneath),
  `FernsyTV/Screens/JellyfinOverviewScreens.swift` and `JellyfinSearchScreens.swift` (menus, a
  navigation path for Übersicht), `FernsyTV/Model/TVModel+Search.swift` (`DetailTarget` for a
  Jellyfin episode's series).
- New German strings: "Zur Serie".
- No change to FernsyCore, the player or the Mac app.
