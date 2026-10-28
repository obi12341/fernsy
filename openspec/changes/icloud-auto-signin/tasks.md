# Tasks

## 1. Apple TV

- [x] 1.1 `TVModel.signingInFromICloud` and the launch path in `TVModel+Sync.swift`: lookup within 10 s, provider and Jellyfin sign-in, failure kept as error and offer.
- [x] 1.2 `RootScreen`: "Anmelden …" while `signingInFromICloud`; welcome screen shows the error after a failed attempt.
- [x] 1.3 Debug switch `IPTV_TESTICLOUDLOGIN=demo|jellyfin` (in-memory `LoginBacking`); remove `IPTV_TESTUSESYNCED`; DEVELOPMENT.md.

## 2. Mac

- [x] 2.1 `AppModel.signingInFromICloud` and the same launch path; `FernsyApp` shows progress instead of `LoginView` while it runs.
- [x] 2.2 `LoginView` shows the error after a failed attempt, the iCloud box stays as offer.

## 3. Launch screen

- [x] 3.1 FernsyCore or per app: `ICloudSignInStep` states published by both models; `signingInFromICloud` ends after the catalog and at least 1.5 s, at once on failure.
- [x] 3.2 Apple TV and Mac: launch screen with icon, "Signing in with your iCloud login", the steps (ring / checkmark), cross-fade into the app; German strings.
- [x] 3.3 UI test: the steps appear and are checked off, no welcome screen, Start after at least 1.5 s; screenshot of the screen for the user.

## 4. Verification

- [x] 4.1 Apple TV UI tests on the demo server: `IPTV_TESTICLOUDLOGIN=demo` opens Start without the welcome screen; a rejected login (`IPTV_TESTICLOUDLOGIN=demo-wrong`) shows the welcome screen with the reason and the offer; signing out in Settings shows the welcome screen with the offer, not an automatic sign-in.
- [x] 4.2 Apple TV UI test with the local test Jellyfin (`IPTV_TESTICLOUDLOGIN=jellyfin`): Jellyfin tab without the welcome screen.
- [x] 4.3 Mac: "Fernsy Dev" with `IPTV_TESTICLOUDLOGIN=demo` and an empty keychain opens the library without the login window (window screenshot only).
- [x] 4.4 Full Apple TV UI suite and `scripts/test.sh` green.
- [ ] 4.5 Real Apple TV, dev build without account, Mac's demo login in iCloud: app opens on Start without the welcome screen.
