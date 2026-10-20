# Design

## Context

- `JellyfinClient.deviceId` is a UUID under the UserDefaults key `jellyfin.deviceId`. Debug
  builds share UserDefaults (and the keychain service) with the installed app, so both use the
  same device id. Jellyfin ends all other sessions of a device when that device authenticates
  again, and deleting a device in `/Devices` revokes its tokens. Every debug test run
  (`JF_SERVER/JF_USER/JF_PASS`) and every test clean-up therefore signed the user's installed
  app out – the "expires after 15–20 minutes" the user saw.
- `JellyfinStore.call` marks the session expired on HTTP 401 and the UI shows a sign-in banner.
  Playback (`JellyfinPlayback`) talks to `store.client` directly; `report`, `pingTranscode` and
  `stopTranscode` use `try?`, so a 401 there loses the report silently. The direct-play URL
  carries the token as `api_key`; a revoked token makes the next range request fail.
- Keychain: `Keychain.save/load/delete` with service `de.mobilistics.fernsy`, account
  `jellyfin` holding `JFSession` (no password, by the recorded decision of
  `add-jellyfin-library-browser`).

## Goals / Non-Goals

**Goals:** tests never sign the user out; a rejected token is renewed without the user; no
progress is lost while that happens.

**Non-Goals:** Quick Connect, multiple Jellyfin accounts.

## Decisions

### Separate device id for debug builds
`deviceId` reads `jellyfin.deviceId.debug` in DEBUG builds (and the device name gets a
" (Debug)" suffix), so the server sees the debug build as another device. Test clean-ups remove
only devices with that id.
- Rejected: a separate bundle id for debug builds – breaks the keychain/UserDefaults sharing the
  other debug switches rely on and changes the sandbox container.

### Password in the keychain
A second keychain item, account `jellyfin.password` (same service, generic password,
`kSecAttrAccessibleAfterFirstUnlock`, not synchronised), is written on every successful
sign-in and deleted on sign-out. The `JFSession` item is unchanged, so existing sessions keep
loading. This supersedes the "no password" decision of `add-jellyfin-library-browser`: the user
asked never to sign in by hand again, and Jellyfin offers no refresh token.
Debug runs that keep the keychain (no `FERNSY_NO_KEYCHAIN`) can set `JF_KEYCHAIN_SUFFIX=test`
so their session and password items get separate account names and never touch the user's.
- Rejected: Quick Connect – needs another signed-in device to approve every renewal.
- Rejected: storing the password inside the `JFSession` JSON – changes the stored session format
  and would mix it into debug logs of the session.

### Silent renewal
`JellyfinStore.renewSession()` (single-flight: concurrent callers await the same task) signs in
with the stored server, user name and password, keeps the user id and server data, stores the
new token and clears `isExpired`. `call` catches `unauthorized`, renews once and repeats the
request; on failure (no password, wrong password, user gone) it sets `isExpired` as today. The
debug fake-token switch `JF_TOKEN` keeps working to test this path.

### Playback across a renewal
- `JellyfinClient.report/pingTranscode` return whether they succeeded and throw `unauthorized`;
  `JellyfinPlayback` sends them through a store helper that renews and retries once; the last
  progress report is kept and resent after a renewal, the stop report always gets its retry.
- Direct play: when the engine reports a failure after start and the session was renewed (or a
  401 is seen), `JellyfinPlayback` reloads the direct-play URL with the new token at the current
  position (`engine.load(startAt:)`), at most once per renewal. Transcodes restart with a new
  PlaybackInfo the same way.

### Findings while testing
- This Jellyfin server (12.2) serves `/Videos/{id}/stream?static=true` without any token, so a
  revoked token never breaks direct play there; the reload path matters for servers that
  enforce it and for transcodes. It is exercised with `JF_TESTRECOVER=<s>`.
- Debug builds get a new code signature with every build, so any keychain access by a debug
  build (even to items it created itself) makes macOS ask the user. Keychain behaviour is
  therefore not tested with debug builds; `JF_KEYCHAIN_SUFFIX` exists but should not be used
  while the user is at the Mac. Debug switches for this change: `JF_TOKEN` (invalid token →
  silent renewal), `JF_BADPASS=1` (renewal fails → expired), `JF_TESTRECOVER=<s>`.

## Risks / Trade-offs

- [Password at rest] → keychain only, this device only, never logged; removed on sign-out.
- [Renewal loop when the server keeps rejecting] → one renewal per failed request, single-flight;
  a failed renewal ends in the expired notice.
- [Existing users without a stored password] → the first rejection still shows the notice once;
  signing in stores the password.

## Migration Plan

None beyond the one-time sign-in for existing sessions. Rollback leaves an unused keychain item
that sign-out removes.
