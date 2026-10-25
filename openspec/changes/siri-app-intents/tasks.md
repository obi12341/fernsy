# Tasks

## 1. Shared actions

- [x] 1.1 Extract `Fernsy/App/FernsyActions.swift` from `MCPTools` (visible channels, now/next, guide search, schedule/record now, play with recording check, stop) and make `MCPTools` use it; verify the MCP tools are unchanged by re-running the MCP checks against the demo server (`IPTV_MCP=1 IPTV_MCPTOKEN=test`, `mcpc.py`/`mcprec.py` from the mcp-server change: find/whats_on/search/schedule/refused/cancel/play/blocked) — Done: find/whats_on/search, play 101→102, stop, bad id, blocked by a recording, schedule/refused/cancel/cancel finished/play recording all as before; `play movie:500` now answers "No IPTV film" because the user switched IPTV films off in Settings (correct per the switch)

## 2. Entities and intents

- [x] 2.1 Add `ChannelEntity` (IndexedEntity, string query over visible channels, suggested = favourites + recent) and `ShowEntity`; index visible channels on catalog/visibility/adult changes, clear on sign-out; verify with `IPTV_TESTINTENT=query:<text>` (demo server) that "northern" resolves Northern Light 1 and a channel hidden with `IPTV_TESTHIDE` or marked adult with `IPTV_TESTADULT` does not — Done: "northern" → Northern Light 1; "world" → World View Business, not the adult World View 24 (`IPTV_TESTADULT=103`); "stadium" → only Stadium 2 (Stadium 1 hidden); suggested = favourites + recent
- [x] 2.2 Add `PlayChannelIntent`, `WhatsOnIntent`, `FindShowIntent`, `RecordIntent`, `StopPlaybackIntent` with dialogs (de/en) and snippets; verify each through `IPTV_TESTINTENT=<intent>:<arg>` on the demo server (log of the dialog text; play switches 101→102; with `IPTV_MAXCONN=1 IPTV_TESTRECORD=101:3:60` switching to 102 answers "blocked"; record schedules the current show; restore `recordings.json`, trash test files) — Done: whatson (2 rows), find cooking (3 shows) and an unknown title, play 101/102, play an adult channel refused, stop twice; with one stream and a recording on 101 play:102 says the recording holds the stream and record:104 is refused with the reason
- [x] 2.3 Annotate the player view with the playing channel's entity and donate `PlayChannelIntent` on channel starts; verify `RecordIntent` without a channel records the channel the player shows (`IPTV_AUTOPLAY=live:104` + `IPTV_TESTINTENT=record`) — Done: with `IPTV_AUTOPLAY=live:106` the record intent without a channel schedules the show on now on Stadium 2

## 3. App Shortcuts

- [x] 3.1 `FernsyShortcuts` with German and English phrases in `AppShortcuts.xcstrings`; verify the built app's `Metadata.appintents` lists the five intents and the phrases (inspect with `plutil`/`jq` on the extracted metadata), and that the "no AppIntents.framework dependency" note is gone from the build log

## 4. Integration

- [x] 4.1 Build Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without new warnings; `openspec validate --all --strict`; document `IPTV_TESTINTENT` in `DEVELOPMENT.md`
- [x] 4.2 The spoken phrase needs a real Siri session: the user says "Schalte Fernsy auf ZDF" once with the nightly; everything else is covered by 2.x/3.1 (this does not block archiving) — Left to the user with the nightly; not blocking
