# Design

## Context

See proposal.md for the motivation. What the code does today:

- Start's "Weiterschauen" and its large entry come from `StartBuilder.continueWatching()`; the
  large entry is its first item. Its inputs are `ResumeStore` (provider films and episodes, in
  UserDefaults), `JellyfinStore.resume`/`nextUp` (from the server) and the recorder.
- Provider positions travel through `SyncStore`: all positions are one iCloud value `resume`
  (`{key: {p, d, t, w}}`), merged per item by date. `pullAll()` runs at launch and on
  `NSUbiquitousKeyValueStore.didChangeExternallyNotification`. Every device that sends decodes
  the whole value into its own four fields, merges, and writes the whole value back.
- Jellyfin's rows load in `refreshHome()`, called from a `.task` of Start (when the view
  appears), after a library refresh and after playback.
- Coming back from the background does neither: `TVModel.appBecameActive()` (iPhone, iPad) only
  retries an offline sign-in and refreshes the paired server; the Apple TV's scene-phase handler
  only refreshes the paired server; the Mac has no activation hook.
- An episode's position is stored under `episode.<episode id>`. To list it, `continueWatching()`
  needs `episodeIndex[id]`, built from `seriesInfo` (`seriesInfos` on the Mac): a dictionary in
  memory that is filled only when a series' page loads its episode list. After a relaunch it is
  empty, and for a series opened only on another device it is never filled.
- When a position is saved the series is known everywhere: `PlayItem.Kind.episode(id:seriesId:)`
  on the Mac, `VODItem.episode(episode, show)` on the others.
- `SeriesInfo` is `Decodable` only (it reads the provider's irregular JSON).

## Goals / Non-Goals

**Goals:**

- Coming back to the app shows the positions the other devices have sent, for provider films,
  provider episodes and Jellyfin, without the user doing anything.
- A started provider episode is listed on every device that knows the position, also right after
  a launch and offline.
- Devices running an older version keep working unchanged, and cannot undo what newer ones sync.
- The rules live once in FernsyCore; the Mac model and the shared iPhone/Apple TV model only wire
  them.

**Non-Goals:**

- Making iCloud deliver faster: when iCloud has not yet brought a value to the device, the app
  cannot fetch it; it arrives through the notification as before.
- A general cache of the catalog's details (film details, covers) or a change to the catalog refresh.

## Decisions

### 1. Ask again when the app comes to the front

One function per model, `refreshFromOtherDevices()`, called from `appBecameActive()` (iPhone,
iPad), the Apple TV's scene phase `.active`, and `NSApplication.didBecomeActiveNotification` on
the Mac. It

- calls the new `SyncStore.refresh()`: `synchronize()`, `pullAll()`, `pushLocalChanges()` – the
  same steps as at launch, without registering observers again. Reading the store again takes
  values iCloud already brought to the device while the app was suspended, whether or not the
  notification for them is delivered;
- calls `jellyfin.refreshHome()`, at most once a minute (the Mac is activated with every switch
  between apps; one refresh is three requests plus one per library);
- runs decision 4 (load the series of started episodes).

Start already rebuilds its rows when `resumeRevision` or `jellyfin.homeRevision` change, and the
Top Shelf is written from the same model changes, so no view changes are needed for this part.

Alternatives considered:

- **Polling while the app is in the front.** Rejected: iCloud's notification covers the running
  app (icloud-sync "without a restart while their app runs"), and for Jellyfin it would mean
  requests every few minutes on every device for a row most users look at when they arrive.
- **Refreshing in Start's `.task` only** (as now, plus a scene-phase trigger inside the view).
  Rejected: the model owns the sync and the Jellyfin store; a view-local trigger would miss the
  case where another tab is open, and the Top Shelf.
- **Background refresh or silent pushes.** Rejected: far more machinery (background modes, a
  push sender) for something that is only seen when the app is opened.

### 2. The series of an episode: a value of its own, beside the positions

`ResumeStore` gets `series(ofEpisode:)` and `setSeries(_:forEpisode:)`, kept in UserDefaults as
one dictionary `episodeSeries` (`[episode id: series id]`; the name stays clear of the `resume.`
and `watched.` prefixes that `ResumeEntry.read` and `ResumeStore.started` scan). `SyncStore`
syncs it as the iCloud value `resumeSeries`: on push the union of the remote and the local
dictionary, cut down to episodes that have a position in the merged `resume` value; on pull the
union with the local one. A union cannot lose entries, and two devices never disagree about the
series of an episode.

The series is written

- whenever an episode's position is saved (Mac: where `saveResume` is called for an episode
  item; shared model: `stopVOD` and its periodic saves), and
- whenever a series' episode list is loaded: every episode of it that has a position and no
  series yet gets one. This repairs positions saved by older versions.

Alternatives considered:

- **A fifth field in each entry of `resume`.** Rejected: every device rewrites the whole value
  with the fields it knows. A device on 2.5.1 or older would drop the field for all entries each
  time it sends.
- **Keys of the form `episode.<series id>.<episode id>`.** Rejected: old and new versions would
  keep separate positions for the same episode and no longer sync with each other.
- **Storing enough to show the entry without the episode list** (series name, episode code,
  container extension, image). Rejected: several times the data in a store limited to 1 MB, a
  copy of catalog data that goes stale, and playing needs the provider's current entry anyway.
- **Asking the provider which series an episode belongs to.** Not possible: the API has no such
  request; trying every series would be thousands of requests.

### 2a. Finished items reach the other devices

Found while implementing (2026-11-13, reproduced with two stores on one backing): when an item is
watched to its end, `ResumeStore.save` removes its position and date and sets `watched`.
`ResumeEntry.read` then gives it the date `distantPast`, and `pushLocalChanges` sends only
entries of the last 90 days, so the finished state is never sent. iCloud and the other devices
keep the old position, and the item stays in their "Weiterschauen" for good. The merge rule
"a finished item beats a position from a device that has not seen it finish" exists but never
gets the finished entry.

`pushLocalChanges` therefore also sends a finished local entry when iCloud holds a position for
that key. The merge then turns iCloud's entry into the finished one, and the other devices take
it like any newer value. Older versions decode it (position 0, watched) and apply the same rule.

Alternatives considered:

- **Sending every watched item.** Rejected: the 90-day rule keeps the store small; a library of
  watched films would grow it without bound, and only items another device still lists matter.
- **Keeping a date on finished items** (`resume.<key>.at` left in place). Rejected: `started`
  and `fraction` read the `resume.` keys as positions, and older versions would too.

### 3. Episode lists on disk: `SeriesInfoStore`

New in FernsyCore: `SeriesInfoStore(folder:)` keeps the provider's raw `get_series_info` answer
per series (`<folder>/<series id>.json`) and decodes it with the existing `SeriesInfo` decoder.
The raw answer is kept because `SeriesInfo` is not `Encodable`, and so a later change of the
decoder reads old files too. The folder is in the account's cache folder (Caches: the system may
empty it, then the lists load again).

- `XtreamClient` gets `seriesInfoData(_:)` next to `seriesInfo(_:)`.
- The series pages keep asking the provider when they open (as today) and write the answer to
  the store; if the provider does not answer, they show the kept list.
- Signing out and switching series off for the account remove the folder with the other caches.

Alternative considered: making `SeriesInfo` `Codable` and saving the decoded form. Rejected: a
second encoding to maintain for a type whose decoder exists to absorb provider quirks.

### 4. Loading the series of started episodes

In FernsyCore, `StartedEpisodes.missingSeries(resume:known:catalog:limit:)` returns the series
ids to load: the started episode keys newest first (at most 20), mapped through
`series(ofEpisode:)`, without those whose list is in memory and those not in the catalog. Each
model has `loadStartedSeries()`: for these ids it takes the list from `SeriesInfoStore`, else
from the provider (one request each, one after the other), puts it into its `seriesInfo`
dictionary and counts `resumeRevision` up, so Start rebuilds. It runs after the catalog loaded,
when positions or the series value arrive from iCloud, and from decision 1. Lists from disk are
applied before any request, so a launch shows the row at once.

A request that fails is tried again at the next trigger, not in a loop. Nothing here opens a
stream, so the single-connection rule is not touched.

Alternatives considered:

- **Loading in `StartBuilder`.** Rejected: the builder is a pure function over its inputs and is
  called per redraw of the personal rows.
- **Loading all series with a watched or started episode.** Rejected: unbounded for long-time
  users; the row shows the newest items, and 20 episodes cover it.

### 5. Test hooks

- `IPTV_TESTSYNC=memory` (debug builds): the sync store runs on a dictionary in memory instead
  of iCloud. Test runs are keychain-less, which today means no sync and positions kept in memory
  only (`ResumeStore(defaults: nil)`), so the path from a position to iCloud and back cannot run
  in a UI test. With this switch the resume store and the sync store both use a UserDefaults
  suite of their own (`fernsy.test.sync`), emptied at launch; `IPTV_TESTSYNC=memory-keep` does
  not empty it, for the relaunch checks. Stored settings of the app are not touched.
- Debug MCP tool `sync_from_other_device` (Apple TV, iPhone, iPad): puts positions (and their
  series) into that dictionary as another device would have, without telling the app. The test
  then leaves and reopens the app.
- The Mac has no debug tools: `IPTV_TESTREMOTERESUME=<s>:<key>:<position>:<duration>[:<series id>],…`
  puts them into the dictionary after `<s>` seconds, also silently.
- Log lines (category app) for "took … on coming to the front" and for each series loaded for
  Start, so tests wait for states instead of times.

## Risks / Trade-offs

- [iCloud has not delivered the value to the device when the app is opened] → The notification
  path stays; the row then updates a moment later instead of at once. Not solvable in the app.
- [Positions saved before this version have no series until an updated device opens the series or
  plays the episode] → Decision 2's repair; named in the release note. The user's own started
  series show after they are touched once on any updated device.
- [A device on an older version never writes the series for episodes it starts] → They show on
  other devices once any updated device has the series' list in memory; otherwise not, as today.
- [The kept episode list is older than the provider's] → Start only needs it to name and open a
  started episode; the series page refreshes it. An episode the provider removed is opened with
  its old entry and fails like any removed item.
- [`resumeSeries` grows] → It is cut to episodes with a position on every push; positions older
  than 90 days are not sent, finished ones have no position.
- [More requests at launch] → At most one per series with a started, uncached episode, the first
  time; none afterwards.
- [The Mac's activation fires often] → The iCloud part only reads local values; Jellyfin is
  limited to once a minute.
- [Merge conflicts with `vpn-guard`] → Both touch `AppModel` and `TVModel` near the path monitor
  and launch; resolved by whichever merges second. With the guard, `loadStartedSeries()` is
  refused without a VPN like every provider request, and the lists on disk still show.

## Migration Plan

No data migration: existing positions stay as they are and gain their series over time
(decision 2). Rolling back leaves an unused `resumeSeries` value in iCloud and an unused
dictionary in UserDefaults; older versions ignore both.

## Open Questions

- Whether the release note should tell users that series started before the update appear only
  after they were opened once. Decided when the commit is written.

## Notes from implementing

- **Finished items (decision 2a)** were found and reproduced while writing the sync tests: two
  stores on one backing, a film stopped at 20 min on one and watched to the end on the other –
  the first kept 20 min, and iCloud too. Added with the user's agreement (2026-11-13).
- **Where the lists are kept.** Apple TV, iPhone and iPad: `Caches/Fernsy/<account>/series-info/`,
  as designed. Mac: `series-info/` in the account's folder in Application Support, where the Mac
  keeps its catalog cache; the Mac has no Caches folder of its own for the account.
- **Pages ask once per run.** `seriesDetails` returns the list in memory only when it came from
  the provider in this run (`freshSeriesInfo`); a list taken from the device is asked for again
  when its page opens, and the kept one is used when the provider does not answer. On the Mac the
  series page goes through `AppModel.seriesDetails` now instead of the client directly.
- **Offline.** The shared model's offline start (iPhone, iPad) also applies the cached films and
  series now (`applyCachedLibrary`), which `loadStartedSeries` needs to name the series; the
  Films and Series tabs show them offline too, as "Opening without a connection" asks for cached
  content. The Apple TV has no offline start; the offline check of task 3.5 was done on the
  iPhone (task 3.6) instead.
- **Test hooks.** `TestSync` (FernsyCore) holds the suite and a stand-in for iCloud backed by a
  second suite, so `memory-keep` keeps both over a relaunch. In the Apple TV simulator,
  `XCUIApplication.open(URL)` relaunches the app, and the app's `state` stays
  `runningForeground` after Home; the tests use `IPTV_OPEN` at launch and wait for the log line
  "back in the front" instead. Leaving a series page opened by a link needs more than Menu, so
  the old-position test checks the repaired position at the next launch.
- **Log lines** for tests: "back in the front: asking iCloud and Jellyfin again" (app, detail),
  "Start: episodes of series <id> from the device|provider" (app), "episodes of series <id>
  loaded and kept" (catalog, detail), "Start's rows loaded again" (jellyfin, detail).
- **Checked (2026-11-13).** Apple TV UI tests (host, demo server, test Jellyfin) and iPhone UI
  test (VM) as in tasks 3.5–3.7; the Apple TV test (a) fails with the call in the scene-phase
  handler removed. Mac (Fernsy Dev on the host, demo server): positions put in at 15 s were not
  taken until the app was activated, then the film and the episode showed in Continue Watching
  and the large entry; at a relaunch the episode came from the kept list; five activations
  asked the test Jellyfin once.
- **The whole suite (task 5.1, 2026-11-13).** FernsyCore package tests in the VM and FernsyPlayer
  tests on the host: passed. Apple TV UI tests on the host with the test Jellyfin running: 89
  tests, 78 passed, 9 skipped (Fernsy Cloud), 2 failed. `LibraryUITests.testFilmResumesAndStartsOver`
  failed because the new Jellyfin test set the fixture film's position to 0 afterwards, and that
  test relies on the position the previous run left; the new test now restores the earlier
  position, and both pass in the suite's order. `JellyfinOverviewUITests.testNextPosterShowsAtTheEdge`
  fails the same way on `main` (checked in a separate worktree), so it is not this change's.
  iPhone UI tests in the VM: the seven playback tests and `StartClockUITests` failed there as
  before; on the host `FernsyiOSUITests`, `AssistantUITests.testRequestPlaysItsChannel` and
  `StartClockUITests` passed. No existing test sets `IPTV_TESTSYNC`.
- **Real iCloud (task 5.2, 2026-11-14).** Release builds of this branch on the user's Mac (run
  from the build folder) and Apple TV; the iPhone was not reachable for installing, so the
  Apple TV took its place as the device coming back to the front. The user reported the
  positions watched on the Mac showing up there as expected; how long iCloud took was not
  measured.
