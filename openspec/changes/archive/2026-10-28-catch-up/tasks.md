# Tasks

## 1. Rules (FernsyCore)

- [x] 1.1 `LiveChannel.archiveDays`, `AccountInfo` server time zone and `time_now`, `XtreamClient.archiveURL(channel:start:minutes:)`, `Archive.isPlayable` (design 1, 2); unit tests incl. a server in another time zone and a show older than the archive.
- [x] 1.2 `EPGStore` keeps past entries of archive channels up to their days and loads past days on demand (design 5); unit test of the kept range.

## 2. Demo server

- [x] 2.1 `demo-server/worker.js`: channels 101–103 with archives of 5, 3 and 1 days, programme back that far, `/timeshift/` route, 404 for other channels (design 9); checked locally with a request per case.
- [x] 2.2 The user deploys it (`CLOUDFLARE_ACCOUNT_ID=… CLOUDFLARE_API_TOKEN=… demo-server/deploy.sh`); afterwards the app's tests run against it.

## 3. Playback (FernsyPlayer)

- [x] 3.1 `ArchiveSource`: on-demand playback with the show's timeline, seeking past the download re-requests from the target minute (design 3).
- [x] 3.2 `TunerPool` owner `.archive` and the existing question when connections are held (design 4).

## 4. Mac

- [x] 4.1 Clock symbol in the channel list and the guide's channel column; "Archive: 5 days" in the channel info (design 7).
- [x] 4.2 Day stepper back to the longest archive; "Play from Start" in the show details and double-click on playable past shows; player title (design 6, 8).

## 5. Apple TV

- [x] 5.1 Clock symbol in the channel list and the guide's channel column (design 7).
- [x] 5.2 Guide pages back into the archive with the day title; a click on a playable past show plays it in the on-demand player (design 6, 8).

## 6. Strings

- [x] 6.1 New texts in both apps' catalogs with German translations ("Play from Start", "Archive", "Archive: %lld days", day titles); `LocalizationTests` green.

## 7. Verification

- [x] 7.1 Apple TV UI test, demo server (deployed, 2.2; until then a local run of the worker on 127.0.0.1:8787, which the test prefers): the guide shows the clock symbol on channel 101, Left pages into yesterday, clicking yesterday's 20:15 show plays it (`player.state` playing, MCP `now_playing` names the show); a seek of +10 minutes continues; screenshots.
- [x] 7.2 Apple TV UI test, demo server with `IPTV_MAXCONN=1` and `IPTV_TESTRECORD=104:0:600`: starting an archived show asks before stopping the recording.
- [x] 7.3 Mac, Fernsy Dev on the demo server (`scripts/dev-run.sh`, `IPTV_SECTION=live`, `IPTV_LIVEMODE=guide`): window screenshots of the clock symbol and of the guide one day back; an archived show started with `IPTV_TESTSWITCH`-style debug start plays (log shows the timeshift request).
- [x] 7.4 Full Apple TV UI suite, `scripts/test.sh` and the Mac build green.
- [ ] 7.5 The user checks one archived show of their provider (one real stream, only while their own Fernsy plays nothing), on Mac and Apple TV.
