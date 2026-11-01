# Proposal

## Why

A paired Fernsy Server keeps the IPTV login it got when it was paired. When the user changes the
password at the provider or moves to another account, the server's recordings fail ("login
refused") and the only way out is to remove the server and pair it again with a new code –
on a NAS in the cupboard, which means finding its status page or log again.

## What Changes

- The server's settings in every app (Mac, iPhone/iPad, Apple TV) show which IPTV login the
  server records with (user name and provider address, never the password).
- A "Use This Login" action hands the server the login the device signs in with, through the
  same end-to-end encrypted control channel as the orders; no new code, no visit to the server.
- The server checks the new login with the provider before it takes it: a refused login is
  reported and the old one stays.
- When the server reports that the provider refuses its login, the apps point to that action.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `headless-recorder`: the paired server's IPTV login can be replaced from an app. (The
  capability is introduced by the open change `headless-recorder`, which is archived first.)

## Impact

- FernsyShared: a new control item kind for the login, the login's display form in the
  server's status.
- Fernsy Server: applies a newer login item after checking it, reports the result.
- FernsyCore `ServerModel`, the three apps' server settings, their string catalogs.
- Fernsy Control: no change (it stores the item like any other).

## Out of scope

- Typing a different login on the server's status page (it stays read-only).
- Several IPTV logins on one server, or choosing a login that is not the device's own.
- Jellyfin.
