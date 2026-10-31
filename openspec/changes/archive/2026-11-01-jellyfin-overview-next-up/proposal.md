# Proposal

## Why

On Apple TV, the next episode of a series is easy to reach from Start, which has a "Nächste
Folge" row (Jellyfin's Next Up). The Jellyfin tab's Übersicht has no such row: a user who wants
to go on with a series there has to open the series and find the episode. The user found this
hard. The Übersicht on iPad, iPhone and the Mac lacks the row as well.

## What Changes

- Jellyfin's Übersicht shows "Nächste Folge" (English "Next Up") right below Weiterschauen, with
  Jellyfin's next episodes: series name, "S1 E2 · episode title" as on Start, the episode's
  still or the series backdrop. Selecting one plays the episode.
- The same on all three platforms: Apple TV, iPad and iPhone (which show the Apple TV's
  Übersicht), and the Mac.
- The row uses the list that Start already shows (`JellyfinStore.nextUp`), so both always agree.
  It refreshes when Start's does, for example after an episode ends.

Out of scope:
- Changing the order or the rules of Jellyfin's Next Up (the server decides).
- The episode label "S1 F2" that is hard-coded on Apple TV and iOS; it is noted as a separate
  fix in `code-structure-cleanup` and the new row will show whatever label Start shows.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: "Jellyfin overview on Apple TV" gains the Nächste Folge row. iPad and iPhone follow
  through "Jellyfin on iPhone and iPad", which shows the Apple TV's views.
- `jellyfin-library`: "Jellyfin overview on the Mac" gains the Nächste Folge row.

## Impact

- `FernsyTV/Screens/JellyfinOverviewScreens.swift`, `FernsyiOS/JellyfinSearchViews.swift`,
  `Fernsy/Views/JellyfinOverviewView.swift`: one row each, next to Weiterschauen.
- Strings: "Next Up" already exists with "Nächste Folge" in the Apple TV and Mac catalogs.
- UI tests on Apple TV and iOS (with the local test Jellyfin, which the overview tests already
  need) and a Mac check.
