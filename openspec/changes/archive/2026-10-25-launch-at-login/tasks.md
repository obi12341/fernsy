# Tasks

## 1. Login item

- [x] 1.1 Add `Fernsy/App/LoginItem.swift`: status (`enabled`, `requiresApproval`, `off`), `setEnabled(_:)` via `SMAppService.mainApp`, open Login Items settings; debug builds never register, `IPTV_TESTLOGINITEM` fakes the status; document the switches in `DEVELOPMENT.md`; verify a Debug run with `IPTV_TESTLOGINITEM=enabled` logs the faked status and `sfltool dumpbtm | grep -i fernsy` shows no new entry
- [x] 1.2 Detect a login launch in `AppDelegate` (Apple Event `keyAELaunchedAsLogInItem`, or `IPTV_TESTLOGINLAUNCH=1`) and close the library window so `MenuBarSupport` runs without a window; verify a demo-server run with `IPTV_TESTLOGINLAUNCH=1` shows no library window (window list via `wins <pid>`) and the menu bar item, and a scheduled recording (`IPTV_TESTRECORD=<channel>:60:60`) starts

## 2. Settings

- [x] 2.1 Add "Beim Anmelden öffnen" to the menu bar section of `RecordingSettings`, reading the status on appear and when the app becomes active; approval hint with "Anmeldeobjekte öffnen …"; sync `Localizable.xcstrings` (English: "Open at Login", "Open Login Items …", hint); verify with `IPTV_TESTSETTINGS=recordings` and each `IPTV_TESTLOGINITEM` value (window screenshots)

## 3. Integration

- [x] 3.1 Build Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without new warnings; `openspec validate --all --strict`
- [x] 3.2 The user checks with a nightly/DMG build: turn the switch on, log out and in → Fernsy runs in the menu bar without a window; remove it in System Settings → the switch shows off; if the window still opens at login, apply the fallback from design.md
