# Proposal

## Why

Many Xtream providers keep the last days of some channels (`tv_archive`, `tv_archive_duration`
in the catalog) and serve any past stretch on request (`/timeshift/…`). Fernsy reads the flag
but only shows it in the channel info. The user's provider has 199 such channels, 192 of them
German, with 1, 3 or 5 days (catalog cache of 2026-10-19). Watching a show that already ran
("Sendung verpasst") is what users miss most in an IPTV app (user request 2026-10-28).

## What Changes

- Channels with an archive are marked with a clock symbol in the channel list and in the guide
  (Mac and Apple TV), with the archive's length in the channel's info.
- In the guide, past shows on such channels within the archive window can be played from their
  start: on Apple TV a click on the show, on the Mac "Play from Start" in the show's details and
  a double-click. Past shows outside the window, or on channels without an archive, stay as
  today (dimmed, nothing to play).
- The guide reaches back as far as the archive does: the Mac's day stepper and Apple TV's paging
  go back up to the longest archive among the shown channels (at most 7 days); the past
  programme of archive channels is kept for that long.
- An archived show plays in the player like a film: a timeline over the show, pause, and seeking
  within it; the title names the show, channel and day.
- It takes one of the account's streams like a channel: when recordings hold them all, the same
  question as for live TV.
- Only a channel's own archive counts (user decision 2026-10-28: no fallback to a sibling channel
  with the same programme id, e.g. "Das Erste HDraw" to "Das Erste HD").
- The demo server gets archive channels and the `/timeshift/` route for tests.

Out of scope: recording or downloading archived shows; rewinding live TV past the local buffer
into the archive (a later change); archive for channels without their own flag.

## Capabilities

### New Capabilities

- `catch-up`: archive channels marked, past shows played from the provider's archive, on Mac and
  Apple TV.

### Modified Capabilities

- `program-guide`: day navigation reaches back into the archive.
- `demo-server`: archive channels and the timeshift route.

## Impact

- FernsyCore: `XtreamClient.archiveURL(channel:start:minutes:)`, `LiveChannel.archiveDays`,
  the EPG cache keeps past days for archive channels, archive rules (which shows are playable).
- FernsyPlayer: an archive item plays as on-demand (`isLive: false`); seeking beyond what is
  loaded requests the archive again from the new position.
- Fernsy (Mac): channel list and guide marks, day stepper backwards, "Play from Start", player
  title; stream-limit question.
- FernsyTV: channel list and guide marks, paging back, click on past shows, player overlay.
- Demo server (`demo-server/worker.js`): `tv_archive` on some channels, programme further back,
  `/timeshift/<user>/<pass>/<minutes>/<YYYY-MM-DD:HH-MM>/<id>.ts`; deploying it needs the
  Cloudflare token (the user runs `demo-server/deploy.sh`).
