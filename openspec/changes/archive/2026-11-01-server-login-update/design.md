## Context

- Pairing (headless-recorder design 4) hands the server the control key, the cloud key and one
  IPTV login, sealed to the server's key; the server keeps them in `secrets.json` and reports
  through its `server` status item. Orders and states travel as items sealed with the control
  key, one writer per kind (design 3).
- The server already learns when the provider refuses its login (it reports the error "IPTV
  login refused" in its status) but cannot get a new one without a new pairing.
- Every device that holds the control key also holds the user's IPTV logins already (iCloud
  login sync); the control key reaches no one else.

## Goals / Non-Goals

**Goals:** replace the login from any app in one step; never lose a working login to a typo;
make a refused login visible where the user would look.

**Non-Goals:** a second pairing path; telling the server about logins it should not use.

## Decisions

### 1. A `login` item in the control space
The app writes one item, kind `login`, id `login`: the credentials and the time it was sent,
sealed with the control key like orders. The server applies an item whose time is newer than the
login it uses and newer than its pairing. Apps are its only writer, as for orders.
Rejected: a new pairing mailbox round (needs a code from the server, which is exactly what this
avoids); sealing to the server's own key (the app does not keep the server's public key after
pairing, and the control key already limits readers to the user's devices and the server).

### 2. The server checks before it switches
On a new `login` item the server asks the provider for the account (`player_api` without
action) with it. Accepted: it stores the login in `secrets.json`, refreshes the stream limit
from that answer and reports it. Refused or not reachable: it keeps the old login, and its status
carries the outcome for that item's time (`refused` or `unreachable`; unreachable is tried again
on the next poll, at most for an hour).
Rejected: switching blindly (a typo would stop every recording until noticed).

### 3. What the status shows
The `server` status item gets the login's display form, `user @ host` (no password), and the
outcome of the last login item (time and result). The apps show "Records with: user @ host",
"New login refused" when the last item was refused, and, when the server's error is a refused
login, a note with the "Use This Login" action. The action sends the device's current IPTV login
(the one it is signed in with); without one it is not shown.
Rejected: sending the password back in the status (nobody needs to read it there).

### 4. Running recordings
A new login applies from the next connection: a running recording keeps its connection; when it
reconnects (or the next recording starts) it uses the new login.

## Risks / Trade-offs

- [The login item stays in the space] → it is ciphertext under the control key, which only the
  user's devices and the server hold, all of which already know the user's logins; it is
  replaced by the next one and removed with the space.
- [Two devices send different logins] → the newer one wins, as with any item; the settings show
  which login the server uses, so the user sees the outcome.
- [Provider unreachable when the item arrives] → retried on later polls for up to an hour, then
  reported as unreachable; the old login stays.

## Migration Plan

Servers before this change ignore the unknown item kind and keep their login; apps show no login
line for a status without one. Ships with or after headless-recorder.
