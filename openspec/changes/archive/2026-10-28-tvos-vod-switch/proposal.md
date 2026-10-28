# Proposal

## Why

On the Mac, Settings › Accounts › IPTV has the switches "Filme" and "Serien" (catalog spec,
"IPTV films and series can be switched off"): users who watch films and series through
Jellyfin turn the provider's huge, unsorted VOD lists off. The Apple TV app always loads and
shows them, so the same user sees two Filme tabs worth of clutter there, and each device has to
be set up on its own. With icloud-sync in place, the switch can follow the user to every device.

## What Changes

- Apple TV: Settings › IPTV Account gets the switches "Filme" and "Serien", on by default.
- A switched-off kind is not downloaded or cached on the Apple TV, and does not appear: its tab
  (Filme or Serien), Start's rows (spotlight, Zuletzt hinzugefügt, category rows, Bestbewertet,
  Weiterschauen entries of provider films or episodes) and the search leave it out. Favourites,
  watched marks and resume positions are kept. Switching it on again downloads it right away.
- Both switches sync through iCloud between Mac and Apple TV ("Mit iCloud abgleichen"), as
  app-wide values like the recording padding. A switch changed on one device applies on the
  others while they run: the Mac drops or downloads the kind as if switched there.

Out of scope: hiding single films, series or film/series categories; switching off live TV;
Jellyfin's films and series (they have their own account); a per-account switch (the Mac's
switch is app-wide and stays so).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: new requirement for the films and series switches on Apple TV.
- `icloud-sync`: "Synced choices" also covers the films and series switches.

## Impact

- `FernsyTV/Model/TVModel+Library.swift` (load only switched-on kinds, react to a switch),
  `TVModel.swift` (switch properties), `TVModel+Sync.swift` (synced keys, apply arrivals),
  `TVModel+Start.swift` and `StartScreen.swift` (rows), `RootScreen.swift` (tabs),
  `SettingsScreen.swift` (AccountScreen rows), search index in `JellyfinSearchScreens.swift`.
- `Fernsy/App/AppModel.swift`: the two keys join `syncedKeys`; arriving values are applied to
  `showsIPTVMovies`/`showsIPTVSeries`.
- String catalog of the Apple TV app (German), FernsyTVUITests.
