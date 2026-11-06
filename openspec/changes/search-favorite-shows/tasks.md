# Tasks

## 1. Search model

- [x] 1.1 `SearchResults` gets show hits (entry + channel); `SearchModel` keeps the visible favourites (at most 50) from its snapshot and scans their loaded guide titles per query in the same detached task (now or later, running first, then start), with title keys cached per channel guide
- [x] 1.2 On the first non-empty query of a search session, load the favourites' full guides (`EPGStore.load`, timeout 20 s; it skips fresh guides and reads its disk cache first — the channel list alone loads only now/next) in the background and re-run the current query when it returns; no load per keystroke, nothing when every favourite is loaded
- [x] 1.3 Unit tests (`ShowSearchTests`, FernsyCore) for matching, order, the 50-channel cap, ended shows and channels without guide; hidden channels and adult categories are left out because the favourites come from the same filtered channel snapshot as the channel group (no Mac test target to test it apart)

## 2. Results view

- [x] 2.1 "Shows" group after channels with show rows (logo, title, day and time, channel, "running" badge, planned-recording dot), 20 rows and "show all"
- [x] 2.2 Click: running → play the channel; later → confirmation to record via `Recorder.schedule(...).present()`, or remove a planned one; context menu play / record or remove / show in guide (Live TV guide on that channel)
- [x] 2.3 German strings ("Sendungen", "läuft", "Aufnehmen?", …) in `Fernsy/Localizable.xcstrings`
- [x] 2.4 Checks and screenshots use the existing Mac switch `IPTV_TESTSEARCH=<query>[|<query>…]` (types the queries into the toolbar search); no new switch

## 3. Verification

- [x] 3.1 Fernsy Dev against the demo server (`scripts/dev-run.sh IPTV_FAVORITES=live:101,live:105 'IPTV_TESTSEARCH=the|tennis|news'`): "the" 17 shows on 101, "tennis" 7 on 105, "news" (only on 103, not a favourite) none – read from the search log line (no window screenshot: this session has no screen-recording permission)
- [x] 3.2 `IPTV_TESTSHOWSELECT=running` with "gala" plays live:101; `=later` with "the" asks and plans "The Great Puzzle Duel" with padding (list_recordings, then cancelled); `IPTV_TESTEPGDELAY=6`: 0 shows at first, 7 once the guides arrived after 6.4 s; `IPTV_FAVORITES=` gives no shows
- [x] 3.3 `scripts/vm.sh scripts/test.sh` and the Mac app build

## 4. Wrap-up

- [ ] 4.1 DEVELOPMENT.md (search covers the favourites' shows); `openspec validate --all --strict`; archive, merge into `main`, push (with the user's consent)
