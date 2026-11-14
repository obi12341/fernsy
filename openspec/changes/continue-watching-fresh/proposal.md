# Proposal

## Why

Coming back to Fernsy on the iPhone after watching on the Mac, Start still shows the old
"Weiterschauen" row and with it the old large entry. Three gaps cause it: nothing asks iCloud or
Jellyfin again when the app comes back from the background; a started provider episode can only
be listed while its series' episode list is in memory, which is gone after every relaunch; and
for the same reason a series started on another device is never listed here at all. A fourth
gap was found while implementing: a provider film or episode watched to its end on one device
stays in "Weiterschauen" on the others, because the finished state never reaches iCloud.

## What Changes

- When the app comes back to the front (iPhone, iPad, Apple TV) or is activated (Mac), it takes
  what iCloud has from the other devices and loads Jellyfin's rows of Start again, so
  "Weiterschauen", "Nächste Folge" and the large entry show the current state without the user
  switching tabs. On the Apple TV the Top Shelf follows, as it is built from the same rows.
- A resume position of a provider episode remembers which series the episode belongs to, on the
  device and through iCloud, in a value of its own that older app versions leave alone.
- Start lists started provider episodes without the user opening their series first: it loads the
  episode lists of the series that have a started episode, and keeps loaded episode lists on the
  device, so they are there at the next launch, also without a connection.
- Positions saved by older versions get their series as soon as an updated device has that
  series' episode list (its page was opened) or plays the episode again.
- A provider film or episode watched to its end on one device leaves "Weiterschauen" on the
  others: the finished state is sent while iCloud still holds a position for it.

Out of scope:

- Polling Jellyfin or iCloud while the app stays open in the front: positions arrive there as
  before (iCloud's notification; Jellyfin when Start appears).
- Finding the series of an old position by asking the provider for every series: the provider has
  no lookup from an episode to its series.
- Jellyfin positions through iCloud (they live on the server), positions of recordings and Fernsy
  Cloud recordings on other devices, and Handoff.
- The format of the synced positions, and the rule which of two positions wins. Only which
  local entries are sent changes (finished ones whose position iCloud still holds).
- Start's other rows (Zuletzt hinzugefügt, categories, Bestbewertet) and the catalog refresh.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `icloud-sync`: changes from other devices are also taken when the app comes back to the front;
  the series of a started episode is synced with its position; an item finished on one device
  is finished on the others.
- `catalog`: "Weiterschauen" lists started provider episodes without their series having been
  opened on this device, also after a relaunch and without a connection.
- `jellyfin-library`: Start's Jellyfin rows follow the server when the app comes back to the front.

## Impact

- `Packages/FernsyCore`: `SyncStore` (a refresh, the episode-to-series value), `ResumeStore`
  (the series of an episode), a new store for episode lists on disk, `StartBuilder` inputs; unit
  tests for each.
- `FernsyTV`/`FernsyiOS` (shared model): saving the series with a position, loading started
  series, the foreground hooks (`appBecameActive`, the Apple TV's scene phase), debug hooks.
- `Fernsy` (Mac): the same in `AppModel`, on `NSApplication.didBecomeActive`; the series page
  writes the episode list it loads to the new store.
- iCloud key-value store: one more value (`resumeSeries`), small (episode id to series id for
  started episodes).
- Requests to the provider: at most one `get_series_info` per series with a started episode that
  is not cached yet (the series of the 20 newest started episodes). No stream is opened.
- Debug switches and a debug tool for tests, documented in DEVELOPMENT.md.
- Both this change and `vpn-guard` touch the models' launch and network-path code; the second to
  merge resolves small conflicts there.
