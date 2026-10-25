# Tasks

## 1. Keep-awake rule

- [x] 1.1 Add `Recorder.keepAwakeHoursKey` (default 6, 0 = always, -1 = off) and use it in `updateActivity()`; the activity reason names the nearest recording and is renewed when that changes; re-evaluate when the setting changes; `IPTV_AWAKEHOURS` sets it in memory; document the switch in `DEVELOPMENT.md`; verify with the demo server: `IPTV_TESTRECORD=<channel>:7200:60 IPTV_AWAKEHOURS=3` → `pmset -g assertions | grep -i fernsy` shows the assertion, with `IPTV_AWAKEHOURS=1` it does not
- [x] 1.2 Verify release after the last recording: `IPTV_TESTRECORD=<channel>:10:30 IPTV_AWAKEHOURS=1` → assertion during the recording, gone within one scheduler tick after it ends (`pmset -g assertions` before, during, after); `IPTV_AWAKEHOURS=0` with a recording 2 days ahead keeps it, and `IPTV_AWAKEHOURS=off` shows no assertion even during the recording

## 2. Settings

- [x] 2.1 Add the "Mac wach halten" picker to `RecordingSettings` with its footnote (lid on battery, Apple menu › Sleep; for "Aus" the warning that a recording stops when the Mac sleeps) and adjust the menu bar footnote; sync `Localizable.xcstrings` with English ("Keep Mac awake", choices, notes); verify with `IPTV_TESTSETTINGS=recordings` (window screenshots, light and dark via `IPTV_APPEARANCE`)

## 3. Integration

- [x] 3.1 Build Debug, "Fernsy Direct" and Release (`CODE_SIGNING_ALLOWED=NO`) without new warnings; `openspec validate --all --strict`
- [x] 3.2 The user checks in their own build: schedule a recording a few hours ahead, leave the Mac idle past its sleep time → it stays awake and records; afterwards it sleeps again
