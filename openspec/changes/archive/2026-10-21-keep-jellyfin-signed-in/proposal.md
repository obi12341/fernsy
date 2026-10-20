# Proposal

## Why

The user's Fernsy lost its Jellyfin session every 15–20 minutes: resume positions were no longer
saved and the next episode only played after signing in again. Jellyfin tokens do not expire on
their own; the session was ended by the debug builds used for testing – they share UserDefaults
and therefore the Jellyfin device id with the installed app, every debug sign-in made the server
end the other sessions of that device, and the test clean-up removed that device. Independent of
the cause, the user wants to never sign in by hand again, and a revoked token currently loses
playback progress silently.

## What Changes

- Debug builds use their own Jellyfin device id, so test sign-ins and clean-ups never end the
  installed app's session.
- **BREAKING (recorded decision):** Fernsy stores the Jellyfin password in the keychain together
  with the session (reverses "never store the password" from `add-jellyfin-library-browser`).
- When the server rejects the token, Fernsy signs in again with the stored password without
  asking and repeats the request; only if that fails (password changed, user removed) does it
  show the expired notice.
- Playback keeps working through a renewal: progress, stop and ping reports are retried after
  signing in again, and a direct-play stream that fails with "unauthorized" resumes at the same
  position with the new token.
- Signing out removes the password as well.

Out of scope:
- Quick Connect or other password-less sign-in.
- Accounts signed in before this change have no stored password: they need one manual sign-in
  (then never again).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `jellyfin-account`: the session is kept with the password and renewed automatically; sign-out
  also removes the password; debug builds identify as a separate device.
- `jellyfin-playback`: reporting playback survives a renewed session.

## Impact

- `Fernsy/Jellyfin/JellyfinStore.swift` (stored credentials, silent renewal, retry),
  `JellyfinClient.swift` (device id, report errors surfaced), `JellyfinPlayback.swift` (retry
  reports, restart direct play after 401), `Fernsy/Support/Keychain.swift` (if needed),
  `README.md`, the archived design's decision is superseded in this change's design.
- Testing practice: clean-ups remove only the debug device.
