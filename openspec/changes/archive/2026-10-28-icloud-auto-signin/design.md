# Design

## Context

- Both apps already look for logins in iCloud at launch (`refreshSyncedLogins`, through
  FernsyCore `LoginSync`, CloudKit with encrypted fields) when they have no account, and put
  what they find into `syncedXtream` / `syncedJellyfin`. The login screens (Mac `LoginView` box
  "Aus deiner iCloud", Apple TV `SignInScreen` `SyncedLoginsRow`) offer them with "Übernehmen".
- Mac: `FernsyApp` shows `LoginView` while `credentials == nil && !hasJellyfin`. Apple TV:
  `RootScreen` shows "Anmelden …" while `signIn == .signingIn && startedWithAccount`, else the
  welcome screen.
- The lookup is asynchronous; on a fresh device CloudKit can take seconds to answer, or not at
  all (offline, no iCloud account).
- `IPTV_TESTUSESYNCED=1` (debug) already takes the offered logins automatically on a real
  Apple TV; it was the manual stand-in for exactly this behaviour.

## Goals / Non-Goals

**Goals:**
- At launch without an account: sign in with what iCloud has, no welcome or login screen, no
  cancel.
- Never strand the user: without a usable iCloud login the normal screens show.

**Non-Goals:**
- Syncing sign-outs; several stored logins; changing `LoginSync`.

## Decisions

1. **A launch state "looking in iCloud".** Each model gets `signingInFromICloud`, true from
   launch when there is no account on the device (no keychain credentials, no Jellyfin
   session), `LoginSync` is backed (sync allowed) and "Zugangsdaten abgleichen" is on. While it
   is true the root shows the existing "Anmelden …" progress (Apple TV `RootScreen`, Mac
   `FernsyApp`) instead of the welcome or login screen. It ends after the lookup and the
   sign-ins, successful or not. Rejected: showing the welcome screen and signing in when the
   answer arrives; the screen would flash and could take a click meant for something else.

2. **Only at launch, at every launch without an account** (user decision 2026-10-28). Signing
   out during a session shows the welcome or login screen with the "Übernehmen" offer, so the
   user can sign in to another account; signing in stores that login in iCloud (as today), so the
   next launch uses the new one. No "first launch" flag. Rejected: only on the very first
   launch; the user wants the iCloud login whenever the device has none.

3. **Lookup with a 10-second limit.** `isAvailable()`, then `xtream()` and `jellyfin()` in
   parallel, all within 10 s; past that the normal screens show, and logins that arrive later
   are offered as today, not used. Rejected: waiting without limit; an Apple TV without network
   would hang on "Anmelden …" with nothing to cancel.

4. **Provider and Jellyfin independently, both before the progress ends.** The provider login
   goes through the normal `signIn(credentials, remember: true)` (keychain, catalog), Jellyfin
   through `jellyfin.signIn` as its own device. If one fails, the other still counts: with one
   account signed in the app opens normally, and the failed one stays as an offer in Settings ›
   Add Account (Apple TV) / the accounts settings (Mac).

5. **Failure shows the reason.** If no account could be signed in, the welcome or login screen
   shows with the sign-in error of the provider (or Jellyfin) and the iCloud logins as offers.
   A server that is down and a rejected password look the same to the user here; both say why.

6. **Test switch replaces `IPTV_TESTUSESYNCED`.** Debug builds take `IPTV_TESTICLOUDLOGIN=demo`
   (`demo-wrong` for the demo server with a wrong password, `jellyfin` for the local test Jellyfin): `LoginSync` gets an
   in-memory backing holding that login, so UI tests run the real launch path in the simulator
   without iCloud. `IPTV_TESTUSESYNCED` is removed, the new path does what it did.

7. **A launch screen with steps, at least 1.5 s, until the channels are there** (user decision
   2026-10-28, after a first version flashed past). The model publishes the steps
   (`ICloudSignInStep`: found, provider signed in, Jellyfin signed in, channels loaded, each
   pending, running or done), and the shared look is one view per app: Fernsy icon, title, the
   steps with a ring while running and a checkmark when done. `signingInFromICloud` stays true
   until the provider's catalog is loaded (Apple TV `signIn` and Mac `login` already await it) and
   1.5 s have passed since launch, so the screen covers the moment the tabs or library would
   appear empty; the root then switches with a cross-fade (0.4 s). Without a provider login the
   channel step is left out. A failure ends the screen at once (no minimum), so the reason
   shows without delay. Rejected: a longer fixed delay (3 s+), which makes a fast launch slow;
   ending at sign-in, which showed an empty Live TV for a moment.

## Risks / Trade-offs

- [A user who wants to try another provider on a device keeps getting the iCloud one at
  launch] → sign out and sign in with the other account in the same session; it then replaces
  the iCloud login on all devices. Turning off "Zugangsdaten abgleichen" stops it entirely.
- [Slow CloudKit on first launch] → up to 10 s of "Anmelden …"; in tests on real devices the
  answer took 1–3 s.
