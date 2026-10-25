# Design

## Context

Fernsy already keeps running without windows (`applicationShouldTerminateAfterLastWindowClosed`
returns false; `MenuBarSupport` hides the Dock icon when the menu bar item is on and no window
is open). The library is a `WindowGroup("Fernsy", id: "library")` that SwiftUI opens at launch.
Settings are SwiftUI tabs in `LoginView.swift`; the menu bar switch (`MenuBarSupport.enabledKey`)
sits in `RecordingSettings`.

## Goals / Non-Goals

**Goals:**
- A login item that the user controls in Fernsy and in System Settings, with one truth.
- A quiet start at login: no window in the user's face, recordings still run.

**Non-Goals:**
- Starting before login, waking the Mac, or a helper app.

## Decisions

- **`SMAppService.mainApp`** (`register()`/`unregister()`, `status`). It works sandboxed, needs
  no helper bundle and is App Store compliant when the user turns it on (guideline 2.4.5:
  no auto-launch without consent, hence off by default).
  Rejected: a login helper app with `SMLoginItemSetEnabled` (deprecated, extra target) and a
  LaunchAgent plist (not allowed in the sandbox).
- **macOS is the source of truth.** The switch reads `SMAppService.mainApp.status` when
  Settings appears and when the app becomes active; nothing is stored in `UserDefaults`.
  `.requiresApproval` shows the hint and `SMAppService.openSystemSettingsLoginItems()`.
  Rejected: a stored Bool (drifts as soon as the user removes the item in System Settings).
- **Detecting a login launch:** in `applicationWillFinishLaunching`, the current Apple Event is
  `kAEOpenApplication` with `keyAEPropData == keyAELaunchedAsLogInItem` when macOS opens a login
  item. If so, the library window is closed as soon as it appears (before it is shown where
  possible) and `MenuBarSupport` takes over as when the user closes the last window.
  Rejected: `.defaultLaunchBehavior(.suppressed)` on the library window (it would also apply to
  normal launches) and a "start hidden" preference (a user opening Fernsy by hand would get no
  window).
- **Debug builds:** `LoginItem` does not call `register`/`unregister` (a debug bundle in
  DerivedData would become a real login item, and debug builds must not change the user's
  system). The switch keeps its state in memory and logs. `IPTV_TESTLOGINLAUNCH=1` treats the
  launch as a login launch; `IPTV_TESTLOGINITEM=<enabled|approval|off>` fakes the reported
  status for the Settings UI.

## Risks / Trade-offs

- [The Apple Event flag may not be set for `SMAppService.mainApp` items on macOS 27] → verified
  in task 3.2 with a nightly build at a real login. Fallback if it is missing: treat a launch
  within 60 s of the user session's start (`kern.boottime` is not enough; use the console
  session start time) as a login launch, recorded in this design before implementing it.
- [A window flashes briefly at login] → close in `applicationWillFinishLaunching`/first
  `didBecomeKey`; acceptable if it is visible for a frame.
- [The DMG build moved or copied elsewhere] → `SMAppService.mainApp` registers the bundle by
  identity; macOS follows a moved app. A second copy (Downloads and Applications) can be the one
  that starts; documented as a support note, not handled.
