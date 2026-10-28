# Tasks

## 1. Apple TV model

- [x] 1.1 `TVModel`: `showsIPTVMovies` / `showsIPTVSeries` from `library.iptvMovies` / `library.iptvSeries` (missing = on), stored on change; `IPTV_SHOWMOVIES` / `IPTV_SHOWSERIES=0|1` in memory only.
- [x] 1.2 `loadLibraryCatalog`: fetch only switched-on kinds, store `[]` for the others; switching off empties the kind's arrays (and `seriesInfo`), switching on downloads it at once (after a running load) and rewrites the cache.

## 2. Apple TV UI

- [x] 2.1 `MainTabs`: Filme and Serien tabs only while their switch is on.
- [x] 2.2 Settings › IPTV Account: "Films" and "Series" rows with on/off value and the footnote; German strings.
- [x] 2.3 Check Start (spotlight, Recently Added, category rows, Best Rated, Continue Watching) and the search leave out a switched-off kind.

## 3. Sync

- [x] 3.1 Add both keys to `syncedKeys` on Mac and Apple TV; apply arrivals in `syncArrived` by assigning the properties.
- [x] 3.2 FernsyCore test: a Bool key syncs between two SyncStores and an equal write-back is not sent again.

## 4. Verification

- [x] 4.1 UI test on the demo server (`launchDemo`): switch Films off in Settings → Filme tab gone, search for a demo film finds nothing; switch on → tab back with films. Second test with `IPTV_SHOWSERIES=0`: no Serien tab, no series on Start.
- [x] 4.2 Full Apple TV UI suite and `scripts/test.sh` green.
- [ ] 4.3 Real devices, dev builds, demo account (`IPTV_SYNC=1` where needed): switch Series off on the Mac → Apple TV drops the Serien tab within seconds; switch it on on the Apple TV → Mac's sidebar shows Series again and downloads them.
