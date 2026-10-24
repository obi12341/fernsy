# Tasks

## 1. Sign-in

- [x] 1.1 Account type cards, privacy footer, field-specific errors with red outlines for IPTV and Jellyfin. Verify: a debug run without credentials (`FERNSY_NO_KEYCHAIN=1`, no `IPTV_SERVER`) shows the login screenshot; a debug switch `IPTV_TESTLOGIN=<server>|<user>|<pass>` submits the form. Wrong demo password → error under user/password. `http://127.0.0.1:9` → error under server (screenshots).

## 2. Settings

- [x] 2.1 TabView settings (Konten, Wiedergabe, Aufnahmen with the menu bar toggle, Jugendschutz with the detected categories). Verify: a debug switch `IPTV_TESTSETTINGS=<tab>` opens Settings on that tab (screenshot of Jugendschutz on the demo account).

## 3. Menu bar

- [x] 3.1 Drawn TV symbol with a red dot while recording; quit warning in the menu. Verify: build. The user checks the menu bar during a recording.

## 4. Localization and verification

- [x] 4.1 Strings (de + en), with no stale keys. README switches. Debug/Release builds. `openspec validate redesign-settings-login-and-menus --strict` and `openspec validate --specs --strict`.

## Workflow follow-up

- `/opsx:archive`, then commit, merge into main and push, only after the user agrees.
