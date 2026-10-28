# Design

## Context

- `PlayerEngine` (FernsyPlayer, shared by Mac and Apple TV) publishes `status` (`idle`,
  `loading`, `playing`, `paused`, `buffering`, `ended`, `failed(message)`), `isReconnecting`,
  `reconnectAttempt` (of `maxReconnectAttempts` = 8), `connectionHealth` (`ok`, `slow`, `silent`,
  `reconnecting(loadBalancer:)`) and `showsServerSwitchNote`.
- The Mac's `PlayerScreen.statusOverlay` turns these into the cards of "Player status cards" and
  "Stall cause in the player"; the stall card waits 1 s of live buffering (`stallCardVisible`).
  Network state comes from `AppModel.isNetworkAvailable` (`NWPathMonitor`, `IPTV_TESTNOPATH=1`
  fakes no network).
- On Apple TV, `PlayerScreen` (live, recordings) and `VODPlayerScreen` (films, episodes,
  Jellyfin) draw only the video, the overlays and an invisible `player.state` marker for tests.
  Both screens are themselves focusable and handle the remote (`onMoveCommand`, `onExitCommand`).
- A Jellyfin item resolves its playback (`JellyfinPlayback.make`) before the engine loads: for
  that moment the engine is still `idle` while `playingVOD` is set.
- Live TV's preview pane plays through the same engine (`model.previewing`).

## Goals / Non-Goals

**Goals:**
- The Mac's status, with the same rules and texts, on both Apple TV players and the preview.
- Readable from the sofa: centered, large, on a dark card where text is shown.

**Non-Goals:**
- Changing when the engine reconnects, judges a stall or fails.
- Sharing view code with the Mac (AppKit-era layout, mouse buttons, different sizes).

## Decisions

1. **One `PlayerStatusLayer` view for both Apple TV players.** It takes the engine, the title, an
   optional live channel (for the logo) and the two actions, and draws in the middle of the
   screen: the loading block (logo, large spinner, "<title> wird geladen …"), the plain spinner,
   the reconnect card, the stall card, the failure card, and the server-switch note at the top.
   The order of cases follows the Mac's `statusOverlay` so both platforms say the same thing at
   the same moment. The layer carries a `player.status` accessibility marker naming what it shows
   (`loading`, `spinner`, `reconnecting`, `stall`, `offline`, `failed`, `none`) for the UI tests,
   next to the existing `player.state`. Rejected: moving the Mac's view into a shared package (its layout, sizes and
   buttons are made for a window and a mouse; only the decision of *which* card shows is worth
   sharing, and that is a short switch).

2. **Loading also covers "about to load".** The layer shows the loading block while the engine
   is `loading`, and also while the screen has an item but the engine is still `idle` (Jellyfin
   resolving its stream). Without this a Jellyfin film would show black for a second or two.

3. **Stall card after one second, as on the Mac.** A live `buffering` starts a 1 s timer; only
   then, and only if connection health or the network gives a cause, the stall card replaces the
   spinner. Short stalls stay a spinner.

4. **Network state in `TVModel`.** An `NWPathMonitor` sets `isNetworkAvailable`, with
   `IPTV_TESTNOPATH=1` in debug builds, the same switch as on the Mac.

5. **Focus on the failure card.** While the status is `failed`, the player screen stops being
   focusable and the card becomes a focus section whose first button ("Erneut versuchen") gets
   focus; Back on the card stops playback as Back in the player does. When the status leaves
   `failed`, focus returns to the player. Pitfall: inside the player view, under its `onMoveCommand`,
   `onTapGesture` and `onExitCommand`, focus never moved between the card's buttons (the arrows
   reached the player's handler; passing `nil` there was not enough). The layer therefore sits
   beside the player in an outer `ZStack`, not inside it. Rejected: Up/Down shortcuts without visible buttons
   (the Mac shows buttons; on the remote, buttons are what users try first).

6. **Actions.** "Erneut versuchen" for a live channel releases the player's tuner and tunes the
   channel again (as `AppModel.retuneForPlayer` + play on the Mac); for a film, episode or
   Jellyfin item it plays the item again from its saved position; for a recording it plays it
   again. "Nächster Sender" tunes the next channel of `zapChannels` through `zap(to:)`, so a
   recording holding the stream still asks first.

7. **Preview pane spinner.** The pane shows a spinner over the channel's artwork while the
   previewed channel's engine status is `loading` or `buffering`; no texts or cards (the pane is
   small and the full player is one click away).

8. **Strings in the Apple TV catalog.** The Mac's English texts are reused word for word, so
   translators and both apps say the same; German translations as on the Mac.

## Risks / Trade-offs

- [The spinner over a frozen last frame during zapping looks like a stuck picture] → the loading
  block dims the video behind it a little, so the picture reads as "waiting", not as playing.
- [Focus jumping to the failure card while the user browses the channel strip] → the card only
  takes focus when no overlay (strip, tracks) is open; it shows without focus otherwise.
- [Test switches that make the provider slow also run in CI's slower simulator] → UI tests wait
  on the `player.status` marker's value instead of fixed sleeps.
