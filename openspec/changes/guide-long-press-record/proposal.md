# Proposal

## Why

In the guide on iPhone, iPad and Apple TV a show that is running now cannot be recorded: tapping
it plays the channel, and the record options (the sheet on iPhone and iPad, the dialog on the
Apple TV) only open for later shows. A show that just began is exactly the one a user may want to
record. The Mac does not have this gap: its guide's context menu offers Record and Record on
Server for running shows too.

## What Changes

- A long press on a show in the guide of iPhone and iPad opens a menu: Watch Channel (running
  show), Play from Start (past show of an archive channel), Record on Fernsy Server or Cancel
  Recording (when the server already has an order), and Details. It works on every show
  (running, later, archived), so the gesture means the same everywhere.
- A long press on a show in the Apple TV guide opens a menu with the same choices for the Apple
  TV: Watch Channel / Play from Start, Record or Stop Recording (running show) and Record or
  Don't Record (later show) on the Apple TV itself, Record on Fernsy Server or Remove from Server,
  and Details for the show's dialog.
- Tapping (clicking on the Apple TV) stays as it is: a running show plays its channel, a later
  one opens its sheet or dialog, a past archived one plays from its start.
- The Mac is unchanged.

Out of scope:

- Recording on the iPhone or iPad itself: they record only through Fernsy Server (unchanged).
- Changing what tapping does, the Mac guide, the channel lists, Start and the search results.
- New rules for the account's stream limit: a server order that would start now is refused with
  its reason while the device uses all streams, and the Apple TV asks before taking a connection,
  as today.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ios-app`: the guide on iPhone and iPad gets a long-press menu on its shows, so a running show
  can be ordered on Fernsy Server.
- `apple-tv`: the Apple TV guide gets a long-press menu on its shows, so a running show can be
  recorded there or on Fernsy Server.

## Impact

- `FernsyiOS/GuideView.swift` (context menu on the show cells), using the existing
  `ServerRecordButton` logic (order, cancel, refusal message) and `ShowDetailSheet`.
- `FernsyTV/Screens/GuideScreen.swift` (context menu on the show cells), using
  `TVModel.recordNow`, `schedule`, `recorder.stop` and `ServerDialogButtons`.
- UI tests in `FernsyiOSUITests` and `FernsyTVUITests`; strings in both languages.
- No change to FernsyCore, the server protocol or the Mac app.
