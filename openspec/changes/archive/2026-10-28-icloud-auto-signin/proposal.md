# Proposal

## Why

With icloud-sync, a new Apple TV or Mac finds the user's provider and Jellyfin logins in iCloud,
but still shows the welcome or login screen and waits for a click on "Übernehmen". The user
already decided to keep their logins in iCloud ("Zugangsdaten abgleichen"); asking again on every
device is a needless step, and on Apple TV the welcome screen first suggests typing with the
remote.

## What Changes

- Mac and Apple TV: at launch without an account, the app looks for logins in the user's iCloud
  and signs in with them directly. Meanwhile it shows "Anmelden …" instead of the welcome or
  login screen, with nothing to cancel.
- The progress is its own screen, not a bare spinner: the Fernsy icon, "Anmelden mit deinem
  iCloud-Zugang" and the steps with checkmarks as they finish ("Zugang in iCloud gefunden",
  "Bei <server> angemeldet", "Bei Jellyfin <server> angemeldet", "Sender laden …"). It stays at
  least 1.5 seconds and until the channels are loaded, then fades into Start, so the launch does
  not jump between screens.
- This applies at every launch without an account, also after the user signed out on the device
  in an earlier session. Within a session, signing out shows the welcome or login screen with the
  existing "Übernehmen" offer, so the user can sign in with another account; that login then
  replaces the one in iCloud.
- Provider and Jellyfin are taken independently: whatever iCloud has is used.
- The welcome or login screen shows when iCloud has no login, is not available, does not answer
  in time, "Zugangsdaten abgleichen" is off, or the sign-in fails (then with the reason, the
  login kept as an offer).

Out of scope: syncing sign-outs between devices; choosing between several stored logins (iCloud
holds one per kind); Jellyfin sessions (each device still signs in as its own device).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `icloud-sync`: "Synced accounts" signs in with the iCloud logins at launch instead of offering them.
- `apple-tv`: "First launch and sign-in on Apple TV" no longer shows the welcome screen when iCloud has a login.

## Impact

- `FernsyTV/Model/TVModel.swift`, `TVModel+Sync.swift`, `FernsyTV/Screens/RootScreen.swift`
  (launch state and progress screen); `Fernsy/App/AppModel.swift`, `Fernsy/App/FernsyApp.swift`
  (same on the Mac); `IPTV_TESTUSESYNCED` becomes unnecessary.
- FernsyCore `LoginSync` unchanged; a timeout around its lookup at launch.
- UI tests need a way to provide an iCloud login without iCloud (debug switch).
