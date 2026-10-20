# Tasks

## 1. Setup

- [x] 1.1 Get credentials (scratchpad only), pick a test film and back up its user data; check the server's device list and note which device is the user's installed app (it must survive every test)

## 2. Debug device

- [x] 2.1 Debug builds use `jellyfin.deviceId.debug` and a "(Debug)" device name; verify a debug sign-in (`JF_SERVER/JF_USER/JF_PASS`) creates its own device and the installed app's device stays in `/Devices`

## 3. Stored password and renewal

- [x] 3.1 Keychain item `jellyfin.password` written on sign-in, deleted on sign-out; verify with a debug run that does not use `FERNSY_NO_KEYCHAIN` only against the debug keychain item names (`JF_KEYCHAIN_SUFFIX=test` keeps them apart from the user's), then remove them — sign-in wrote both items (seen); a debug build touching keychain items makes macOS ask the user for access (new code signature per build), so sign-out deletion was checked by code review and the test items were removed with `security`; later keychain tests: none with debug builds
- [x] 3.2 `renewSession()` and retry in `call`; verify by revoking the debug device's token on the server (delete only the debug device) while the library is open: the next request renews silently, no expired banner; and with a wrong stored password the expired banner appears — `JF_TOKEN` (invalid token) renews silently, `JF_BADPASS=1` ends with expired; a real revocation of the debug device was renewed by the next progress report

## 4. Playback

- [x] 4.1 Reports, ping and stop go through renew-and-retry; direct play and transcodes continue after a renewal; verify by revoking the debug device during playback of the test film: playback continues, and the position after stopping is on the server — after revoking the debug device the progress report renewed the session, a seek kept playing, the server got 7017 s after stopping; this server serves `static=true` streams without a token, so the reload path was checked with `JF_TESTRECOVER=8` (renewed, reloaded at the same position)

## 5. Finish

- [x] 5.1 Translations if any new strings, README (debug device, password in the keychain, `JF_KEYCHAIN_SUFFIX`), update the memory note about test clean-ups (delete only the debug device)
- [x] 5.2 Restore the test film's user data, remove debug devices and keychain test items, verify the installed app's device is still on the server, remove credentials and verify nothing secret is in the repository or logs

## Workflow follow-up

- Archive after the user's review, then merge `change/keep-jellyfin-signed-in` into `main` with the user's OK.
