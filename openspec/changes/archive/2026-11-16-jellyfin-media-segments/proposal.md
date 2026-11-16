# Proposal

## Why

When a Jellyfin episode ends, Fernsy shows the next episode only once the file has played to its
very end, so every binge sits through the full end credits (often 2–5 minutes). Intros and
recaps cannot be skipped. Jellyfin already knows where these parts are: since 10.10 the server
publishes media segments (Intro, Recap, Outro/credits, Preview, Commercial) through
`/MediaSegments/{itemId}`, filled by providers such as the Intro Skipper plugin. On the
developer's server (Jellyfin 12.4, Intro Skipper 12.0.6.0) every one of 30 sampled episodes has
segments, nearly all with credits. Fernsy ignores them.

## What Changes

- Fernsy reads an episode's media segments from the server when playback starts. Embedded
  chapters named like credits ("Credits", "End Credits", "Ending", "Abspann") are the fallback
  when the server has no credits segment. Without either, the end of the file stays the trigger,
  as today.
- **Next episode at the credits:** the next-episode card appears when the final credits begin.
  The credits block is the last Outro segment plus any Outro or Preview segments right after
  it. Outro segments that end well before the final block (false detections mid-episode) are
  ignored. When the block reaches the end of the file (within about 10 s), the card counts down
  and starts the next episode. When more of the episode follows (a scene after the credits),
  the card only offers the next episode, without a countdown. "Watch Credits" closes the card
  and lets the episode play to its end, with no second card at the end.
- **Played when leaving in the credits:** moving on to the next episode, or closing the player,
  during the final credits marks the episode as played on the server, even when the position is
  below Jellyfin's 90 % threshold (e.g. Andor S2E12 at 89.9 %).
- **Skip Intro / Skip Recap:** while an Intro or Recap segment plays, the player shows a button
  that jumps to its end. On Apple TV it takes focus, so Select skips.
- **One next-episode card on every platform:** the episode's image, series, season and episode,
  title, and a countdown ring, with "Play Now" and "Watch Credits" (or "Cancel" at the end of
  the file). The Mac, iPhone/iPad and Apple TV cards share this content and behavior.
- **Faster switch:** while the card shows, Fernsy loads the next episode's details and playback
  information, so it starts without a loading pause.
- **Still watching?** After three episodes in a row that the countdown started without any input
  from the user, the next card asks "Are you still watching?" instead of counting down.
- **Settings** (Settings › Jellyfin Server on each platform): "Play Next Episode Automatically"
  (on by default; off shows the card without a countdown) and "Skip Intros and Recaps" with Show
  Button (default), Automatically and Never.
- The assistant's `now_playing` reports the countdown also while the credits still play.

### Out of scope

- IPTV (Xtream) series: they have no segments; their end-of-file countdown on Apple TV stays as
  it is.
- Films: no next item, and no skipping of their credits.
- Skipping Commercial or Preview segments with a button (Preview only joins the credits block).
- Intro Skipper's own HTTP endpoints of old plugin versions (`/Episode/{id}/IntroSkipperSegments`),
  servers before Jellyfin 10.10, and any client-side detection of intros or credits.
- Writing segments to the server, or changing Intro Skipper's settings.
- Picture in Picture: the card and the skip button are not drawn into the PiP window (the
  countdown still runs and starts the next episode, as today).
- An assistant tool for skipping segments (the assistant can already seek).

## Capabilities

### New Capabilities

None. The behavior belongs to the existing Jellyfin playback capability.

### Modified Capabilities

- `jellyfin-playback`: "Next episode" moves to the credits with the new card and its rules; new
  requirements for reading media segments, skipping intros and recaps, marking played when
  leaving in the credits, "Still watching?" and the two settings.
- `apple-tv`: new requirements for the credits card and the skip button (Play Now focused,
  Select skips) and for Back on them (closes the card = Watch Credits; the skip button is not
  part of Back).
- `ios-app`: a new requirement for the credits card and the skip button (also with hidden
  controls).
- `mcp-server`: "Next episode in now_playing" also covers the countdown during the credits.

## Impact

- FernsyCore: `JellyfinClient` gains media segments (`GET /MediaSegments/{itemId}`) and chapters
  (`Fields=Chapters` on the detail request); new `JFMediaSegment`/`JFChapter` models; a pure,
  unit-tested rule that turns segments, chapters and the runtime into credits/intro/recap marks.
- FernsyPlayer: `JellyfinPlayback` observes the position against those marks, owns the credits
  countdown, the played mark, the auto-start counter and the prefetch of the next episode.
- Apps: one shared next-episode card and skip button design across `Fernsy/Views/
  NextEpisodeOverlay.swift`, `FernsyTV/Screens/VODPlayerScreen.swift` and
  `FernsyiOS/PlayerView.swift`; two new settings in each app's Jellyfin settings; German strings.
- MCP: `now_playing` while the credits play.
- Tests: the local test Jellyfin's fixture episodes get chapters; UI tests on tvOS and iOS, a
  Mac check, and unit tests for the rule with the shapes seen on the real server.
- No new entitlement, dependency or server-side requirement; servers without segment providers
  behave as today.
