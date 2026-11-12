# Proposal

## Why

A paired Fernsy Server is meant to be the place a show can be recorded from any device
(`recordings` › "Recording on a Fernsy Server": "scheduling a show in any app SHALL offer the
server"). Today that holds only in part: the Mac offers the server in the guide's detail and
nowhere else, and the assistant, the MCP server and the Shortcuts actions know only the device's
own recorder – on iPhone and iPad the assistant answers that the device does not record, even with
a paired server.

## What Changes

- **Mac: the server wherever a show can be recorded.** Beside the guide's detail, the server is
  offered in the record questions of the search and of Start, in the context menus of the guide
  grid, the channel list, the search results and the channel pane's upcoming shows, and next to
  the record button of the channel pane's current show. A show that already has a server order
  offers "Remove from Server" in the same places.
- **One way to order.** Every button and tool goes through one shared step that looks at the
  server's current orders first, so a show ordered on another device is not ordered twice, and that
  says why when the order cannot work right now.
- **Stream limit when the recording would start now.** Ordering a show whose recording window has
  begun, while this device and the server's running recordings already use all of the account's
  streams, is refused with the reason instead of cutting into what plays. Shows that start later
  are not affected (the server applies its own rules at the start).
- **Assistant and MCP.** `schedule_recording` takes where to record: this device or the server.
  Without it, a device that records uses itself, and iPhone and iPad use the server.
  `list_recordings` also lists the server's orders, and `cancel_recording` can remove a server
  order that has not started.
- **Shortcuts (Mac).** The "Record Show" action gets an "On Fernsy Server" switch.
- **Server orders marked where shows are listed.** The guides of the Mac, Apple TV, iPhone and
  iPad mark a show the server will record, records or has recorded, and Start marks it among
  tonight's shows; on the Mac the search and the channel pane show it as planned. (Added on
  12 Nov 2026 after the user tried the menus: ordering a show and seeing nothing change in the
  guide read as "nothing happened".)

Out of scope:

- Loading the server's state at launch and when the app comes to the front, error and offline
  messages for the existing buttons on Mac and Apple TV, and the "Not Set Up" label before the
  first load: these are fixes to behaviour the headless-recorder design already describes and
  are done separately, without a change.
- Marking server orders in the search results of iPhone, iPad and Apple TV and in their channel
  lists (they mark no recordings there today).
- The player's "record now" (R) and the Shortcuts action "Record Current Show": they record the
  stream that plays and stay on the device.
- New buttons on iPhone, iPad and Apple TV: their guide, search and Start already offer the server.
- Series or repeating orders, and choosing the padding per order.
- Changes to Fernsy Server itself or to the control service.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `recordings`: beside "Recording on a Fernsy Server", new requirements name the places on the
  Mac, forbid a second order for a show the server already has, and add the stream-limit rule for
  an order that would start now.
- `mcp-server`: a new requirement beside "Scheduling through the assistant" –
  `schedule_recording` takes the place to record, `list_recordings` and `cancel_recording` cover
  server orders.
- `assistant`: "Assistant in every app" – scheduling and cancelling also work on a paired server,
  from every device including iPhone and iPad.
- `siri`: a new requirement for the "Record Show" action's server switch.

## Impact

- `Packages/FernsyCore`: `ServerModel` (shared ordering step, duplicate and stream check),
  `ServerText` (new reasons), `AssistantTools` (tool definitions), string catalog (German).
- `Fernsy/` (Mac): `ServerViews`, `GuideView`, `SearchResultsView`, `StartView`,
  `ChannelListView`, `ChannelDetailPane`, `RecordingsView` (`RecordButton`), `FernsyActions`,
  `MCP/MCPTools`, `App/AppModel+Assistant`, `Intents/FernsyIntents`, `Localizable.xcstrings`.
- `FernsyiOS/ServerViews.swift`, `FernsyTV/Screens/ServerScreens.swift`: the existing buttons call
  the shared step. `FernsyTV/Model/TVModel+Assistant.swift` (also built for iOS): the recording
  tools.
- `cloud-server/assistant-tools.js` is generated from `AssistantTools`
  (`scripts/assistant-tools.sh`); the cloud worker has to be deployed with the new definitions,
  and released app versions keep talking to it (see design, compatibility).
- No new entitlement, no new dependency, no change to the server image or the control worker.
