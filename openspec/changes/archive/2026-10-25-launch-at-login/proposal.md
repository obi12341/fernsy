# Proposal

## Why

Recordings only happen while Fernsy runs. After a restart or a new login, Fernsy stays closed
until the user remembers to open it, and every scheduled recording until then is missed. An
option to open Fernsy at login closes that gap; it is a standard Mac setting users expect.

## What Changes

- Settings › Aufnahmen gets a switch "Beim Anmelden öffnen" (off by default), in the section
  with the menu bar switch.
- Turning it on registers Fernsy as a login item with macOS; turning it off removes it. The
  switch shows what macOS reports, so removing Fernsy under System Settings › General › Login
  Items is reflected in Fernsy.
- If macOS needs the user's approval, Settings says so and offers a button to open the Login
  Items settings.
- Opened at login, Fernsy starts without its window: in the menu bar when the menu bar item is
  on, otherwise with only the Dock icon. Scheduled recordings run as usual.
- Debug builds never register themselves as a login item; test switches simulate it.

Out of scope:
- A background helper or daemon (recordings still need the app itself).
- Waking the Mac or logging in automatically for recordings.
- Turning the option on by default or asking for it at first launch.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `menu-bar`: new requirement "Open at login" (setting, login item state, starting without a
  window).

## Impact

- New `Fernsy/App/LoginItem.swift` (ServiceManagement `SMAppService.mainApp`).
- `Fernsy/App/FernsyApp.swift` (`AppDelegate`: detecting a login launch, closing the window).
- `Fernsy/Views/LoginView.swift` (`RecordingSettings`: switch, approval hint).
- `Fernsy/Localizable.xcstrings`, `DEVELOPMENT.md` (debug switches).
- No new entitlement: `SMAppService.mainApp` works in the App Sandbox for both the App Store
  and the DMG build.
