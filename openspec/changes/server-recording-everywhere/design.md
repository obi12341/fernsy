# Design

## Context

See proposal.md for the motivation. What exists (2.4.1 and `main`):

- `ServerModel` (FernsyCore) keeps the server's status and orders from Fernsy Control and writes
  orders with `schedule(_ order: ControlOrder)`. `isPaired` is true once a status was read.
- Three buttons build a `ControlOrder` by hand and call `schedule`: the Mac's `ServerRecordButton`
  (guide detail only), iOS's `ServerRecordButton` (`ShowDetailSheet`: guide, search, Start) and the
  Apple TV's `ServerDialogButtons` (guide, search, Start). Mac and Apple TV drop errors (`try?`).
  None of them looks for an existing order beyond what the device last read.
- The Mac records in many more places, all through `Recorder.schedule(entry, on:)`: `RecordButton`
  (context menus of the guide grid and the channel list, the channel list's header),
  `RecordCapsule` (channel pane), the record questions of `SearchResultsView` and `StartView`,
  `FernsyActions.schedule` (MCP, assistant, Shortcuts).
- The recording tools are defined once in `AssistantTools` (FernsyCore) and run by `MCPTools`
  (Mac: MCP server and in-app assistant) and `AssistantToolRunner` in
  `FernsyTV/Model/TVModel+Assistant.swift` (Apple TV and iOS; iOS refuses in `requireRecorder`).
  The relay offers the assistant the tool list from `cloud-server/assistant-tools.js`, generated
  from `AssistantTools`; apps send only their platform, not a version.
- The Mac has no UI test target; its flows are checked with debug switches and the log. iOS and
  Apple TV have `ServerUITests` against a dev server.

This change builds on the fix that loads the server's state at launch and when the app comes to
the front (done separately, see proposal). Without it the new items would stay hidden until
Recordings or the server's settings were opened.

## Goals / Non-Goals

**Goals:**

- One code path for ordering a show on the server, used by every button and tool on all
  platforms, so the duplicate and stream rules cannot differ between them.
- The server reachable from every place the Mac records a show, without changing what a plain
  click on "Record" does.
- The assistant and MCP can order, list and cancel server recordings; iPhone and iPad can record
  through the assistant when a server is paired.

**Non-Goals:**

- A setting for "always record on the server" on the Mac or Apple TV.
- Showing server orders as marks in the guide, search or Start.
- Any change to how the server plans, refuses or misses orders (`Planner`).

## Decisions

### 1. `ServerModel.order(show:)` is the only way to order

`ServerModel` gets one entry point that takes the show (`EPGEntry`), the channel, the padding, the
device's name and what the device knows about streams (limit and connections in use), and returns
the order or throws a `ServerModel.OrderFailure` (`notPaired`, `streamsInUse(limit:)`, `locked`,
`network`). It:

1. calls `refresh()` so orders from other devices and the server's running recordings are current
   (one request; the control worker answers a poll without news without writing);
2. returns the existing order when an unfinished one matches channel and start (the rule of
   `order(channelId:start:)`), writing nothing;
3. applies the stream rule (decision 3);
4. writes the order as today.

The three existing buttons and all new callers use it; the raw `schedule(_ order:)` stays for
tests and the server's dev stand-in only. `ServerText` gets the texts for `OrderFailure`, so every
platform says the same.

Rejected: keeping the per-platform `ControlOrder(...)` construction and adding the checks to each
caller (three copies today, eight after this change; the Mac and Apple TV copies already differ
from iOS in error handling). Rejected: de-duplicating on the server only (the apps would still
list two orders until the server's next report, and `Planner` treats orders as independent; a
server change is out of scope and old server images stay in use).

### 2. Mac UI: a second action beside every "Record", never a different click

The Mac records itself, so "Record" keeps scheduling on the Mac with one click. The server is a
second action in the same place:

| Place | Today | Server action |
|---|---|---|
| Guide detail | `recordButton` + `ServerRecordButton` | unchanged (now through decision 1, with errors shown) |
| Guide grid, channel list rows: context menu | `RecordButton` | menu item below it |
| Channel list header (current show) | `RecordButton` (small) | context menu of that button's row |
| Channel pane, current show | `RecordCapsule` (large) | second capsule "On Server" beside it |
| Channel pane, upcoming rows | `RecordCapsule` (small) | context menu of the row |
| Search: record question, row context menu | "Record" | "Record on Server" button / menu item |
| Start: record question | "Record", "Watch Live" | "Record on Server" button |

One small view, `ServerRecordItem` (a plain `Button` titled "Record on Server" or "Remove from
Server", nothing when no server is paired or the show is over), serves menus and
`confirmationDialog`s; the capsule variant shares its action. Failures are shown with
`Prompt.inform`, as `Recorder.ScheduleResult.present()` does for local recordings. The texts
"Record on Server" and "Remove from Server" exist in the catalog already.

Rejected: turning "Record" into a menu ("On this Mac" / "On Fernsy Server") once a server is
paired (every recording would take two clicks, and the R shortcut in the guide would need a
default anyway). Rejected: a global default "record on the server" for the Mac (a setting whose
effect is invisible at the button; iPhone and iPad have that default only because they cannot
record). Rejected: a server capsule in the channel pane's upcoming rows (the rows are narrow; two
capsules crowd the title).

### 3. An order that starts now needs a free stream

Fernsy Server opens its own connection. When the recording window has begun
(`now >= showStart - padBefore`) and `connections in use on this device + channels the server
records now >= limit`, `order(show:)` throws `streamsInUse(limit:)` and writes nothing. The
device's count is its tuner pool's channels with an owner plus a running archive playback
(`TunerPool.owners`, `.archive`); iPhone and iPad count their live playback. The limit is the one
the device uses for its own recordings (`tuners.limit`, `IPTV_MAXCONN` in tests).

The UI says why and changes nothing: "Your account's N stream(s) are in use on this device, so
Fernsy Server cannot record this right now." Tools return `refused` with the same reason. For a
show that starts later nothing is checked: the server applies the stream limit to its own
recordings at the start, and `blockingOrder` already warns before this device plays over a server
recording.

Rejected: asking "Record anyway?" and letting the provider decide which connection survives (on a
single-stream account either the playback or the recording breaks, and the tools cannot ask:
the person may not be at the device, the rule `FernsyActions.playChannel` already follows).
Rejected: offering to stop playback so the server can record (stopping what the user watches is
a larger decision than this button; they can stop and click again). Rejected: no check at all
(the project rule that every design has to work for single-connection accounts).

### 4. Tools: `where` on `schedule_recording`, server orders in the same list

- `schedule_recording` gets the optional `where`: `"device"` or `"server"`. Missing: the device
  when it records (Mac, Apple TV), the server on iPhone and iPad. Every result carries `where`.
  `"server"` without a paired server is an error that names Settings; on iPhone and iPad without a
  server the existing explanation is extended by "or a Fernsy Server".
- The result for the server: `{"result": "ordered", "where": "server", "recording": {…}}`, or
  `"already_ordered"` for an existing order (decision 1), or `"refused"` with the reason
  (decision 3). No `planned_with_shortened_padding`: the server decides about padding at the start.
- `list_recordings` appends the server's unfinished and failed orders after a `refresh()`:
  `recording_id` is `server:<order id>`, `where: "server"`, `status` is the order's phase
  (`sent`, `scheduled`, `recording`, `uploading`, `failed`, `refused`) with `reason` as text.
  Orders that are done are not listed (they are cloud recordings; `play` takes `cloud:<id>`).
  On iPhone and iPad the list holds only server orders instead of refusing.
- `cancel_recording` takes `server:<order id>` and removes an order in phase `sent` or
  `scheduled`; other phases are an error, as for local recordings. The question before
  cancelling (cloud-assistant design 5) is asked for server orders too, on every platform.
- The tool description tells the model when to pass `where: "server"`: the user names the server,
  or says the device will be off or asleep at that time. It never picks the server on its own for
  a device that records.

`AssistantTools` holds the shared parts (argument parsing, the order's JSON, the status names) so
`MCPTools` and `AssistantToolRunner` do not diverge; both call decision 1.

Rejected: a separate tool `schedule_server_recording` (two tools for one action: the model has to
choose on every request, iPhone and iPad would need a failed call to `schedule_recording` first,
and MCP clients see a larger surface). Its one advantage, a clean refusal by released apps, is
covered below. Rejected: separate `list_server_orders` / `cancel_server_order` tools (the user
thinks of one list of recordings; the id prefix already keeps the two apart, as `cloud:` does for
`play`).

### 5. Compatibility with released apps

The relay hands every app version the same tool list. A released app (2.4.1) that gets
`where: "server"` ignores the argument: the Mac and Apple TV schedule on the device, iPhone and
iPad answer that they do not record. So that the assistant does not claim otherwise, the tool
description says that a result without `where` was scheduled on the device, and the answer has to
say where the show is recorded. The MCP server is not affected (its definitions come from the
running app).

Rejected: sending the app's version or a feature list to the relay and filtering tools there (a
second place that has to know which app does what, for a gap that closes with the next update).

### 6. Shortcuts: a switch on "Record Show"

`RecordShowIntent` gets `@Parameter(title: "On Fernsy Server", default: false)`. On, it calls
decision 1 through `FernsyActions` and answers with `ServerText` ("Fernsy Server records …", or
the failure). `RecordIntent` ("Record Current Show") is unchanged: it records the stream that
plays.

Rejected: a second action "Record Show on Server" (one more entry in Shortcuts and Spotlight for
the same thing; a switch reads better in a shortcut).

## Risks / Trade-offs

- [The assistant picks the server when the user did not ask] → the description forbids it for
  devices that record, results always name the place, and the default without `where` is
  unchanged on Mac and Apple TV. Checked with relay requests in both languages (tasks).
- [`refresh()` before every order adds a request and a short wait] → one request to the control
  worker, typically well under a second; the button shows its busy state meanwhile (iOS does
  already). If the request fails, the order fails with `network` rather than risking a duplicate.
- [Stream count is the device's view only] → another device watching at the same moment is not
  seen; the provider then decides, as today. The rule covers the common case (the device the user
  sits at) and is no worse elsewhere.
- [Released apps and `where`] → decision 5; the mismatch ends when the apps update.
- [More menu items on the Mac] → they appear only with a paired server.
- [The worker has to be deployed with the new tool list before the apps ship] → the new apps work
  with the old list too (no `where`: defaults apply), so the order of deploy and release does not
  break anything; only "on the server" by voice needs both.

## Migration Plan

1. Land the shared ordering step and move the three existing buttons to it (behaviour visible:
   errors on Mac and Apple TV, no duplicates, the stream rule).
2. Add the Mac's new places, the tools and the Shortcuts switch.
3. Regenerate `cloud-server/assistant-tools.js` and deploy the dev worker; after the checks, the
   production worker (`cloud-server/deploy.sh --prod`, with the user's agreement).
4. Rollback: the worker's previous tool list can be redeployed at any time; apps then schedule
   with their defaults.

## Notes from implementing (12 Nov 2026)

Assumptions made while the user was away; to be confirmed or corrected in review.

- **Names.** The shared step is `ServerModel.order(_:on:padding:createdBy:streamsInUse:limit:)`
  and returns `(order, isNew)`; the tools need to tell "ordered" from "already_ordered". The
  UI's "already ordered" test is `pendingOrder(channelId:start:)` (unfinished orders only), so
  a show whose order failed can be ordered anew; the guide detail keeps showing any order's
  state through `order(channelId:start:)`, as before.
- **Pitfall: two orders at once.** Fernsy Dev's debug order ran twice (its `.task` runs twice)
  and wrote two orders for one show: both calls had looked before either had written. `place`
  now takes one order at a time (the second waits and finds the first's order); a double click
  would have done the same. Across devices the look-first rule stays the only guard.
- **Pitfall: typed throws.** The project does not infer the error type in `do`/`catch`, so
  `ServerText.order(caught:)` takes what a `catch` holds, and closures that order spell out
  `throws(ServerModel.OrderFailure)`.
- **Record questions have no environment.** `ServerRecordItem` gets the model handed in
  (`app:`) instead of reading it from the environment, so it works inside `confirmationDialog`
  buttons as well as in menus.
- **The channel pane's capsule** reads "On Server" and, once ordered, the order's phase ("Sent
  to the server", "Scheduled on the server"); the pane does not poll, so the phase is the one
  from the last look.
- **Tools.** `list_recordings` maps its filter: "scheduled" also takes orders the server has
  not seen yet ("sent"), "failed" also "refused". A result for a server that is away carries a
  `notice`. The Mac's in-app assistant removes a server order in `AppModel+Assistant` (it has
  to ask first); `MCPTools` removes it without a question, as it does for the Mac's own
  recordings.
- **Shortcuts.** The answer with the switch on is "Fernsy Server records …, <day> <start> to
  <end>" with the show's times (the server applies the lead and follow-up time itself), plus
  the away note when the server has not reported for ten minutes.
- **server/README.md** now names where the server is paired on each device (the Mac: Settings ›
  Recordings) and that the section needs an active subscription: the customer report that
  started this work was about not finding it.
- **Not checked by hand:** the Mac's context menus and Start's record question (the background
  dev app takes no clicks, and the Mac has no UI test target); they use the same
  `ServerRecordItem` as the search's question, which was captured in English and German. The
  relay check with a real model (task 3.4) needs Cloudflare credentials for the dev worker.
