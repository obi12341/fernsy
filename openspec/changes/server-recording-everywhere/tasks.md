# Tasks

Stream tests only against the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`,
`IPTV_USER=demo`, `IPTV_PASS=demo`; `IPTV_MAXCONN=1` for single-stream cases). Control against the
dev worker (`IPTV_CONTROL=https://fernsy-control-dev.mobilistics.workers.dev`, `IPTV_CONTROLKEY`),
Fernsy Cloud against the dev worker (`IPTV_CLOUD=https://fernsy-cloud-dev.mobilistics.workers.dev`,
`IPTV_CLOUDTOKEN`). The server for the checks is the local debug build paired with the stand-in
(`FernsyServer app-pair`, DEVELOPMENT.md › Fernsy Server). Apps run as Fernsy Dev and in the
simulators (`scripts/vm.sh`), never the user's app.

Prerequisite (not part of this change): the fix that loads the server's state at launch and when
the app comes to the front is on `main`; rebase this branch onto it before group 2.

## 1. Shared ordering step

- [ ] 1.1 `ServerModel.order(show:channel:padding:createdBy:streamsInUse:limit:)` with `OrderFailure` (`notPaired`, `streamsInUse(limit:)`, `locked`, `network`): refresh, return an existing unfinished order without writing, stream rule for a window that has begun, then write (design 1, 3). Verify: new `ServerModelTests` with the fake API cover new order, existing order (no `put`), started show with all streams used (no `put`), later show unchecked, started show with room, not paired, failing refresh; `swift test --filter ServerModelTests` in `Packages/FernsyCore` passes.
- [ ] 1.2 `ServerText` texts for `OrderFailure` in English and German in the FernsyCore catalog. Verify: `ServerTextTests` cover each case and `swift test --filter ServerTextTests` passes.
- [ ] 1.3 Move the Mac's `ServerRecordButton`, iOS's `ServerRecordButton` and the Apple TV's `ServerDialogButtons` to `order(show:)`, passing the device's connections in use and limit; show failures on the Mac (`Prompt.inform`) and the Apple TV (`model.notice`) instead of dropping them. Verify: `scripts/vm.sh scripts/ios-uitest.sh "-only-testing:FernsyiOSUITests/ServerUITests"` passes with the dev server's `TEST_RUNNER_*` variables (demo server, `IPTV_CONTROL`, `IPTV_CLOUD`, `IPTV_CLOUDTOKEN`), and the Apple TV and Mac targets build.
- [ ] 1.4 Single-stream check on the Mac: Fernsy Dev with `IPTV_MAXCONN=1`, `IPTV_AUTOPLAY=live:101` and the dev control variables, "Record on Server" in the guide's detail for the show on now. Verify: the alert names the stream in use, the log has no "Fernsy Server: scheduled", `FernsyServer app-list` shows no order and playback continues; the same click for a show two hours later is listed by `app-list`.

## 2. Mac: the server wherever a show is recorded

- [ ] 2.1 `ServerRecordItem` (menu and dialog button: "Record on Server" / "Remove from Server", nothing without a paired server or for a show that is over) and its capsule form, both through `order(show:)` with failures shown (design 2). Verify: the Mac target builds and SwiftUI previews or a debug launch show both states.
- [ ] 2.2 Add the item to the context menus: guide grid, channel list rows and header row, search result rows, the channel pane's upcoming rows. Verify with Fernsy Dev (demo server, dev control, paired local server): each menu shows "Record on Server" below "Record"; with `IPTV_CONTROLKEY` unset (no server) none does.
- [ ] 2.3 Add "Record on Server" to the record questions of the search and of Start. Verify: `IPTV_TESTSHOWSELECT=later` opens the search's question with both buttons (screenshot), and Start's question for a "Tonight" show has it.
- [ ] 2.4 Add the "On Server" capsule beside the channel pane's current show. Verify: `IPTV_SELECT=101` shows both capsules; after ordering, the capsule reads as ordered and a click removes the order (`app-list` empty again).
- [ ] 2.5 Debug switch for the Mac's order path: `IPTV_TESTSCHEDULE=server` (with `IPTV_SELECT=<id>`) orders the selected channel's second upcoming show through `ServerRecordItem`'s action; document it in DEVELOPMENT.md next to `IPTV_TESTSCHEDULE`. Verify: the run logs "Fernsy Server: scheduled …", `app-list` lists the order, and a second run logs that the order exists and `app-list` still lists one.
- [ ] 2.6 German for every new Mac string in `Fernsy/Localizable.xcstrings`. Verify: a launch with `-AppleLanguages "(de)"` shows the new items in German and the catalog has no entry without a German value.

## 3. Assistant and MCP tools

- [ ] 3.1 `AssistantTools`: `where` on `schedule_recording` with the description of when to use the server and what a result without `where` means, the shared helpers for server orders (JSON, `server:<id>` ids, status names) (design 4, 5). Verify: `AssistantToolsTests` cover the definition and helpers; `scripts/assistant-tools.sh` regenerates `cloud-server/assistant-tools.js` and `workerCopyMatches` passes; `node --test cloud-server/test/*.test.js` passes.
- [ ] 3.2 Mac: `FernsyActions.orderOnServer`, `MCPTools` schedule, list and cancel for server orders, and the question before cancelling a server order in `AppModel+Assistant`; update the MCP instructions text. Verify with Fernsy Dev (`IPTV_MCP=1`, `IPTV_MCPTOKEN=test`, demo server, dev control, paired local server) by `tools/call` over HTTP: `schedule_recording` with `where: server` returns `ordered` and `app-list` shows it, a repeat returns `already_ordered`, `list_recordings` contains the `server:` entry, `cancel_recording` removes it, and `where: server` with no server paired returns the error naming Settings.
- [ ] 3.3 Apple TV and iOS: the same three tools in `AssistantToolRunner`; iPhone and iPad default to the server, list only server orders and explain when none is paired. Verify: extend the `IPTV_ASSISTANT_STUB` so a request containing "Server" orders the next show on `live:101` on the server, and a new case in `FernsyiOSUITests/ServerUITests` (dev server variables as in 1.3) sends that request and finds the order in Recordings; `scripts/vm.sh scripts/tv-uitest.sh "-only-testing:Fernsy TV UITests/AssistantUITests"` still passes.
- [ ] 3.4 Relay check on the dev worker: deploy `cloud-server` to dev with the new tool list and ask Fernsy Dev's assistant (demo server, `IPTV_CLOUD` dev, `IPTV_CLOUDTOKEN`, `IPTV_ASSISTANT_CONSENT=1`) in German and English to record a show "on the server" and to record one without naming a place. Verify in the log: the first calls `schedule_recording` with `where: server` and the answer names the server, the second schedules on the Mac.
- [ ] 3.5 Docs: the tools' new behaviour in DEVELOPMENT.md (Assistant, MCP, Fernsy Server), `server/README.md` step 3 (where the server is offered, and by the assistant). Verify: the documented `tools/call` example runs as written against Fernsy Dev.

## 4. Shortcuts

- [ ] 4.1 "On Fernsy Server" switch on `RecordShowIntent` with German title, answering through `ServerText` (design 6). Verify: a new `IPTV_TESTINTENT` step (documented beside the existing ones) runs the action with the switch on against the demo server and the paired local server: the log has the answer "Fernsy Server records …" and `app-list` lists the order; with no server paired the answer says so and nothing is scheduled; the step without the switch still schedules on the Mac.

## 5. Integration

- [ ] 5.1 Three devices on one control space (demo server, dev control and cloud, one `IPTV_CONTROLKEY`): order a show in the Mac's search, order the same show on the Apple TV simulator, ask the iPad simulator's assistant for another. Verify: `app-list` shows two orders, each device's Recordings lists the same two, and removing one on the Mac removes it everywhere within a poll.
- [ ] 5.2 `scripts/test.sh` and `openspec validate --all --strict` pass.

## Workflow follow-up

- Commits with something users notice carry `Release-Note-de` / `Release-Note-en` trailers.
- Deploy the production Fernsy Cloud worker with the new tool list (`cloud-server/deploy.sh --prod`) once the user agrees.
- Archive on `change/server-recording-everywhere`, then merge into `main` and push, each with the user's agreement.
