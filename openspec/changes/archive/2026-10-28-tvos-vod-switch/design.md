# Design

## Context

- Mac: `AppModel.showsIPTVMovies` / `showsIPTVSeries`, stored app-wide in UserDefaults under
  `library.iptvMovies` / `library.iptvSeries` (missing = on). The `didSet` calls
  `catalogSectionSwitched`, which empties the kind and deletes its cache file when off, and
  downloads it when on (waiting for a running refresh).
- Apple TV: `loadLibraryCatalog()` downloads all four lists (film and series categories and
  streams) into one `LibraryCache` file per account and applies it. Films and series feed the
  Filme/Serien tabs (`MainTabs`), Start (`recentlyAdded`, `startRows()`, Continue Watching) and
  the search index (`SearchScreen.buildIndex`, keyed on the counts).
- `SyncStore` mirrors a fixed list of UserDefaults keys (`syncedKeys`, the same list on both
  apps) as `d.<key>` entries with a date; any plist value works, compared with `isEqual`.
  Arrivals reach the apps through `onChange` with the names that came in.

## Goals / Non-Goals

**Goals:**
- Same switches, same keys and same effect on the Apple TV as on the Mac.
- A switch changed on one device applies on the others while they run.

**Non-Goals:**
- Hiding single titles or VOD categories; a per-account switch.

## Decisions

1. **Same UserDefaults keys on both apps, app-wide.** `library.iptvMovies` and
   `library.iptvSeries` join `syncedKeys` on Mac and Apple TV. SyncStore syncs by key name, so
   both apps must use the same names; app-wide like the padding, because the Mac's switch is
   app-wide. Rejected: per-account values through `push`/`pull` like visibility. The Mac would
   need a migration and a second meaning for its switch, for a case (two providers with
   different wishes) nobody asked for.

2. **Apple TV keeps one cache file; a switched-off kind is stored empty.** `loadLibraryCatalog`
   fetches only the switched-on kinds and writes `[]` for the others, so a cache never holds what
   is off and nothing reads the old lists back. Switching on fetches that kind's two lists and
   rewrites the cache. Rejected: one file per kind like the Mac. That changes the cache format
   and the account sign-out cleanup for no user-visible gain.

3. **Switching off empties the model's arrays.** `movies`/`movieCategories` (or the series pair)
   become empty, `seriesInfo` is cleared for series. Tabs, Start and search already derive from
   these arrays, so they follow without their own checks; only `MainTabs` adds the switch to its
   tab condition, so the tab also stays away while the list is empty during a download.
   Continue Watching entries of provider films disappear because they are looked up in `movies`;
   resume positions themselves stay in ResumeStore untouched.

4. **Arrivals are applied like a local switch.** Apple TV and Mac read the two keys again in
   `syncArrived` when `d.library.iptvMovies` / `d.library.iptvSeries` is among the names, and
   assign the property; its `didSet` then drops or downloads as if the user switched there. The
   Mac's `didSet` writes the same value back to UserDefaults, which SyncStore sees as unchanged.

5. **Settings rows as on/off rows.** AccountScreen shows "Films" and "Series" with the
   `ChoiceRow` style used by "Technical Info" (checkmark = on, accessibility value on/off), below
   the account details and above "Sign Out", with the Mac's footnote text.

6. **Debug switches as on the Mac.** `IPTV_SHOWMOVIES` / `IPTV_SHOWSERIES=0|1` set the switches
   in memory only for UI tests, without touching UserDefaults or sync.

7. **The tab bar takes the switches over when Settings is left.** Removing a tab from the
   `TabView` rebuilt the tabs after it: the IPTV Account page closed right after the switch, the
   focus landed on the tab bar and the next Back left the app. `MainTabs` keeps its own copy of
   the switches and updates it on any change only while Settings is not the selected tab, and
   when the selection changes. Rejected: `Tab.hidden(_:)`, unavailable on tvOS; keeping both
   tabs and showing an empty grid, which contradicts "not in the tab bar".

## Risks / Trade-offs

- [A sync arrival while a download runs] → the switch is read again after the download
  (`isEnabled` check before applying), as on the Mac.
- [Turning films off on the Mac surprises an Apple TV user who wanted them] → that is the
  requested behaviour; "Mit iCloud abgleichen" off keeps each device on its own.
