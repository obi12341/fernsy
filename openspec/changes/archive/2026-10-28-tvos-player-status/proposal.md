# Proposal

## Why

On Apple TV the player shows nothing while a channel loads, while playback buffers, while the
connection is restored or when a channel fails: the screen stays black or frozen, and the user
cannot tell whether Fernsy works, waits for the provider or gave up. The player's state exists
(`PlayerEngine.status`, connection health, reconnect attempts), but on Apple TV it only reaches
an invisible marker for the UI tests. The Mac shows all of it ("Player status cards", "Stall
cause in the player"). The user reported it (2026-10-28) and chose the Mac's full set.

## What Changes

- Switching channels (from the strip, Live TV, Start, the guide) shows the channel's logo, a
  spinner and "<channel> wird geladen …" in the middle of the screen until the first picture.
- Buffering during playback shows a spinner in the middle, for live channels, films, episodes,
  Jellyfin items and recordings.
- While the connection is restored: "Verbindung wird wiederhergestellt …", with "Versuch n von 8"
  when the player restarts the stream.
- A live stall that lasts over a second while the channel arrives too slowly, delivers nothing
  or is being replaced shows the card "Der Sender kommt zu langsam vom Anbieter" with what
  Fernsy does about it; without network on the Apple TV the card reads "Keine
  Internetverbindung" instead. When another provider server ends such a stall, a short note
  says so.
- A failed stream shows a card with the reason; a channel offline at the provider explains that
  the provider is the cause. The card offers "Erneut versuchen" and, for live channels,
  "Nächster Sender", reachable with the remote.
- Live TV's preview pane shows a small spinner while the previewed channel loads.

Out of scope: the Mac player (unchanged); the loading picture inside Picture in Picture (no PiP
on Apple TV); new player logic (reconnects, stall detection and their timing stay as they are,
only their display is new).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apple-tv`: a new requirement for the player's status on Apple TV (loading, buffering,
  reconnecting, stall cause, failure with actions) and the preview pane's spinner.

## Impact

- FernsyTV: a status layer shared by the live and on-demand players (`PlayerScreen`,
  `VODPlayerScreen`), the preview pane in `ChannelListScreen`, a network monitor in `TVModel`
  (as `AppModel.isNetworkAvailable` on the Mac, with `IPTV_TESTNOPATH`), retry and next-channel
  actions in `TVModel`.
- FernsyPlayer: none expected; it already publishes status, connection health, reconnect
  attempts and the server-switch note on both platforms.
- Strings: the Mac's texts exist in the Mac's catalog only; the Apple TV catalog gets them with
  German translations.
- UI tests on the demo server with the player's test switches (`IPTV_TESTSLOWSTART`,
  `IPTV_TESTNET`, `IPTV_TESTNODATA`, `IPTV_TRICKLEMORE`, `IPTV_TESTNOPATH`).
