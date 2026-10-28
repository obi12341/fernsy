# Tasks

## 1. Model

- [x] 1.1 `TVModel.isNetworkAvailable` from an `NWPathMonitor`, `IPTV_TESTNOPATH=1` in debug builds (design 4).
- [x] 1.2 Actions: retry for live (release the player's tuner, tune again), films/episodes/Jellyfin (play again from the saved position) and recordings; next channel through `zap(to:)` with the next of `zapChannels` (design 6).

## 2. Status layer

- [x] 2.1 `PlayerStatusLayer` (design 1–3): loading block with logo, spinner and "<title> wird geladen …" (also while a Jellyfin item resolves), plain spinner, reconnect card with attempt, stall card after 1 s with the provider or no-network text, server-switch note, failure card with offline explanation; `player.status` marker; video dimmed behind the loading block.
- [x] 2.2 Live player (`PlayerScreen`) and recordings use it; failure card takes focus only without an open overlay, Back stops (design 5).
- [x] 2.3 On-demand player (`VODPlayerScreen`) uses it, with the same focus rules.
- [x] 2.4 Live TV's preview pane shows a spinner while its channel loads or buffers (design 7).
- [x] 2.5 Strings: the Mac's English texts in `FernsyTV/Localizable.xcstrings` with German translations; `LocalizationTests` stay green.

## 3. Verification

- [x] 3.1 UI test, demo server with `IPTV_TESTSLOWSTART=3`: zapping from the strip shows `player.status` = `loading` with the channel's name, then `none` once playing; screenshot.
- [x] 3.2 UI test, demo server with `IPTV_TESTNODATA=silent:30` (a plain `drop` is bridged seamlessly and shows nothing): the status shows `reconnecting` with "Attempt n of 8", then playback continues; screenshot of the card.
- [x] 3.3 UI test, demo server with `IPTV_TESTNET=trickle:8`, `IPTV_TRICKLEMORE=all` and `IPTV_TRICKLEKBIT=100`: the stall card shows; with `IPTV_TESTNOPATH=1` it reads "No internet connection"; screenshots.
- [x] 3.4 UI test, demo server with `IPTV_TESTNODATA=offline:25`: the offline card shows, "Next Channel" has focus reachable with the remote and tunes the next channel; "Try Again" loads again; screenshot.
- [x] 3.5 UI test, demo server film with `IPTV_TESTSLOWSTART=3`: the loading block shows with the film's title, then playback; the preview pane in Live TV shows its spinner (screenshot).
- [x] 3.6 Full Apple TV UI suite and `scripts/test.sh` green.
- [ ] 3.7 Real Apple TV, Release build: the user switches channels on their provider and judges spinner and cards.
