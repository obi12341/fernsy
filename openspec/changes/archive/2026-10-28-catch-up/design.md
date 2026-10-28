# Design

## Context

- `LiveChannel.hasArchive` is decoded from `tv_archive`; `tv_archive_duration` (days) is not.
  The Mac shows "Archive: available" in the channel info, nothing else uses it.
- Xtream serves an archived stretch at
  `/timeshift/<user>/<pass>/<minutes>/<YYYY-MM-DD:HH-MM>/<stream_id>.ts`. The start is the
  server's local time; `player_api.php` reports it in `server_info.timezone` (IANA name) and
  `server_info.time_now`. Fernsy decodes neither today. Such streams are plain MPEG-TS
  downloads, usually without byte-range seeking.
- The EPG cache (`EPGStore.clean`) keeps entries from 3 hours back to 4 days ahead. The Mac's
  guide steps days 0…3 forward (`GuideView.maxDays`), Apple TV's guide pages back only to its
  default start (`GuideScreen.defaultStart()`), though it can already title "Yesterday".
- Playback: `PlayerEngine.load(url:isLive:startAt:)` plays on-demand files with a timeline; live
  channels go through `TunerPool`, which counts the account's connections per owner
  (`.player`, `.recording`) and drives "ask before taking a connection".
- The demo server streams live channels as a moving window into a looped recording
  (`live(id)`, byte ranges into the media file); it has no archive.

## Goals / Non-Goals

**Goals:**
- One set of archive rules (which shows are playable, the URL, the time zone) in FernsyCore for
  both apps.
- Archive playback that feels like a film: start at the show's start, pause, seek.

**Non-Goals:**
- Rewinding live TV beyond the local buffer into the archive.
- Downloading or recording archived shows.
- Archives of sibling channels (user decision).

## Decisions

1. **`Archive` rules in FernsyCore.** `LiveChannel.archiveDays` (from `tv_archive_duration`,
   0 without the flag) and `Archive.isPlayable(show, on: channel, now:)` (ended or running,
   started within `archiveDays` days, the channel has the flag). `XtreamClient.archiveURL(
   channel:start:minutes:)` formats the start in the server's time zone. Unit tests cover both,
   including a server in another time zone.

2. **Server time zone.** `AccountInfo` decodes `server_info.timezone`; the client keeps it with
   the credentials' session. Without it (the demo server, some panels) the start is formatted in
   UTC, and if `time_now` is given the offset between `time_now` and the device's clock picks the
   zone instead (rounded to 15 minutes). Rejected: always the device's zone (wrong for most
   providers, whose servers run on UTC or their own country's time).

3. **Playing from the archive as on-demand, seeking by re-requesting.** `ArchivePlayback`
   (FernsyPlayer) loads the archive with `isLive: false` through the engine's `ExternalPlayback`
   (as Jellyfin transcodes): `duration` is the show's length, `timelineOffset` the request's
   start within the show, and `restartAt` requests the archive again for every seek, from the
   target's whole minute (the URL's resolution), skipping the seconds into it. Rejected: seeking
   inside what is downloaded (the providers' timeshift endpoints, and the demo server, rarely
   allow byte ranges, so it would work for some providers only); a separate `ArchiveSource`
   (ExternalPlayback already does it).

4. **Stream limit.** `TunerPool` holds an archive connection under its own key (owner
   `.archive`, no live tuner), so it counts against the limit next to live tuners;
   `archiveBlockers()` lists what would have to give way (not the player's own channel, which it
   stops first), and the apps ask as when switching channels. A recording that needs the
   connection treats the archive like the player: it asks, then switches the player to its
   channel, which ends the archive.

5. **EPG reaches back.** `EPGStore` keeps past entries for archive channels up to their
   `archiveDays` (others as today). `get_simple_data_table` already returns the provider's past
   listings; the full table is fetched when a past day is shown and the cache lacks it.

6. **Guide navigation.** Mac: `GuideView` steps back to `-maxArchiveDays` of the shown channels
   (at most 7; 0 without archive channels); past days start at midnight. Apple TV: `page` lets
   Left go back while the window's start is after `now - maxArchiveDays`, and the day title names
   yesterday or the weekday and date.

7. **Marks.** SF Symbol `clock.arrow.circlepath` after the channel's name in the channel list and
   the guide's channel column (Mac: `.secondary`, Apple TV: the tertiary text colour), with the
   accessibility label "Archiv". Playable past shows keep the past dimming but get a small play
   glyph, so it is clear which past shows can be started.

8. **Players.** Mac: `PlayItem.Kind.archive(channelId:start:end:)`, title "<show> · <channel> ·
   <day>"; the guide detail offers "Von vorn ansehen" for playable past shows, double-click plays
   them. Apple TV: `VODItem.archive(EPGEntry, LiveChannel)` through the on-demand player (its
   timeline and status layer); a click on a playable past show starts it. No resume positions:
   archives expire within days.

9. **Demo server.** Channels 101–103 get `tv_archive` 1 with 5, 3 and 1 days; their programme
   reaches that far back; `/timeshift/…` answers with the looped recording as it ran at the
   requested time (the live window function with a fixed start instead of "now"), closed after
   the requested minutes, in UTC (no `timezone` in `server_info`). Deployment needs the
   Cloudflare token and is run by the user.

## Risks / Trade-offs

- [Providers differ in the timeshift URL or time zone] → the time zone comes from the provider,
  the fallback is logged; the user's provider is checked once with a real archive request when
  the user allows a stream (single-stream rule).
- [Seeking re-requests take a moment] → the status layer's spinner shows while it reloads.
- [A paused archive download is closed by the server] → the player pauses reading once it has
  about 24 MB ahead; a server or provider may close that idle connection. The engine's early-end
  recovery then requests the archive again from the position through `restartAt` (seen with the
  local demo worker after ~3 minutes: no rebuffer).
- [More EPG kept on disk] → only for archive channels and only as many days as their archive.
- [Demo deployment] → until the user deploys, archive tests run against a local `wrangler dev` /
  `node` run of the worker or are skipped with a note.
