# Design

## Context

See proposal.md (Why). Current state:

- `JellyfinPlayback` (FernsyPlayer) is shared by all three apps. It loads `nextEpisode` via
  `Shows/{seriesId}/Episodes?startItemId=…&limit=2` and sets `autoplayAt` once the engine reports
  `.ended` (`reportEnd`). Each app draws its own card: Mac `NextEpisodeOverlay` (counts down
  itself and calls `app.play(jellyfin:)`), Apple TV and iOS each a private `NextEpisodeCard` in
  `VODPlayerScreen`/`PlayerView` (their own `countdown` state, `playNext()` → `model.play(next,
  fromStart: true)`).
- Playing the next item builds a new `JellyfinPlayback` through `make`, which calls
  `store.loadDetail` (network) and then `PlaybackInfo` (network) before the stream opens.
- Fernsy never posts session capabilities, so the server lists it with `SupportsMediaControl:
  false` and sends it no remote commands.
- Measured on the developer's server (Jellyfin 12.4, Intro Skipper 12.0.6.0, 30 episodes):
  every episode has segments; shapes seen are Recap at 0, Intro mid-episode after a cold open,
  Outro to the end, Outro followed directly by Preview to the end (One Piece), two Outros where
  the first is a 16 s false hit four minutes early (Dutton Ranch), an Outro ending 26 s before
  the end (Lucky Luke), and episodes with only an Intro. Chapters are rare and agree with the
  segments.

## Goals / Non-Goals

**Goals:**
- One place (FernsyCore) that turns segments, chapters and runtime into marks, unit-tested with
  the real shapes above.
- One owner of the countdown, the played mark and the "still watching" counter
  (`JellyfinPlayback`), so the three apps and `now_playing` all see the same state.
- The apps only draw: the card, the skip button, the short "skipped" notice.

**Non-Goals:**
- Changing how IPTV episodes advance on Apple TV.
- Gapless playback (keeping the decoder open across episodes); the prefetch only removes the two
  network round trips.

## Decisions

### 1. Read segments through Jellyfin's Media Segments API, not Intro Skipper's endpoints

`GET /MediaSegments/{itemId}` (Jellyfin ≥ 10.10) returns `{Items: [{Type, StartTicks,
EndTicks}]}` from every provider: Intro Skipper, chapter-based or EDL providers. Fernsy asks for
all types and keeps Intro, Recap, Outro and Preview.

- Rejected: Intro Skipper's own `/Episode/{id}/IntroSkipperSegments` and `/IntroTimestamps`.
  They only exist in old plugin versions for old servers, and tie Fernsy to one plugin.
- Rejected: detecting credits in the client (black frames, audio fingerprint). The server does
  this once per library; doing it on an Apple TV per playback is slow and duplicates work.

The request runs in parallel with opening the stream and never delays it. A failed or empty
answer means "no segments".

### 2. Chapters as fallback, by name only

The detail request adds `Chapters` to `Fields`. A chapter whose name matches credits
(case-insensitive "credits", "end credits", "ending", "abspann", "outro") marks the credits
start; it ends at the end of the file. Chapters are not used for intros: names like "Opening"
are ambiguous across releases, and every server that has segments covers intros better.

- Rejected: a time-based guess ("last 30 s"), because it cuts off scenes after the credits and
  fires on every episode without credits.

### 3. The marks rule (pure function in FernsyCore)

Input: segments, chapters, runtime. Output: `intro`/`recap` ranges and an optional `credits`
mark `{start, reachesEnd}`.

1. Sort Outro segments; take the last one. Extend its end over directly following Outro or
   Preview segments (gap ≤ 2 s). This is the credits block.
2. `reachesEnd` = block end ≥ runtime − 10 s.
3. Earlier Outro segments are ignored (Dutton Ranch's 16 s hit).
4. Only when there is no Outro: the credits chapter, with `reachesEnd = true`.
5. Segments shorter than 3 s or outside the runtime are dropped.

`reachesEnd == false` (Lucky Luke) shows the card without a countdown. Ten seconds matches the
countdown: a block that ends sooner than that after the countdown would end playback anyway.

### 4. `JellyfinPlayback` owns position-driven state

It already observes the engine. It adds a position check (progress publisher, at most a few
times per second) that publishes:

- `activeSkip: (kind: intro|recap, end)?` while the position is inside such a range.
- `inCredits` once the position enters the credits block. Entering it starts the card: sets
  `nextCardShown`, and `autoplayAt` when `reachesEnd`, automatic play is on and the
  still-watching limit is not reached.
- `creditsDismissed` after Watch Credits / Back. It suppresses the end-of-file card for this
  item. Seeking back before the credits clears it, like the existing "playing again after the
  end" reset.

The end-of-file path (`reportEnd`) stays for items without a credits mark and keeps reporting
the stop right away.

The apps stop keeping their own `countdown` counters. Each card reads `autoplayAt` and calls one
`playNext()` on the playback, which hands the next item to the app through a closure the app
sets. On tvOS/iOS this replaces the local `countdown` state, which also fixes the duplication
that let the Mac and the other apps drift.

### 5. Played mark when leaving in the credits

When the item stops (next episode, close, assistant `play`) while `inCredits` is set, or with a
credits block that reaches the end, Fernsy reports the stop at the real position and then
`POST /UserPlayedItems/{itemId}` (existing `setPlayed`). The item id is the playing item's
fetched id, type-checked as Episode (Jellyfin write safety: never a derived or zero id).

- Rejected: reporting the stop with the runtime as position (a fake 100 %). It would overwrite
  the real position in the session log and does not survive a server's different
  `MaxResumePct`.

### 6. Still watching

A counter in the shared model (`JellyfinStore` or the app model, not the playback, because each
episode gets a new playback): +1 when the countdown starts an episode, reset to 0 on any user
input in the player (play/pause, seek, tap/click, remote press, track change, Play Now). When
it reaches 3, the next card gets no `autoplayAt` and shows "Are you still watching?" with
"Continue Watching", which starts the next episode and resets the counter. Three matches what
Jellyfin's web client and the big services do.

### 7. Skip button

- Shows while `activeSkip` is set, bottom right above the timeline; with the controls hidden it
  shows alone.
- Mac: Return triggers it while it shows (the card's Play Now takes Return only when the card
  shows; the two never overlap because intro/recap are never inside the credits block).
- Apple TV: the button takes focus while the overlay is hidden; Select skips. Moves and swipes
  keep their seek behavior. The button is not part of the Back chain (spec), so Back with only
  the skip button still stops playback.
- iOS: tap.
- Automatic mode seeks once per range per playback (seeking back into the intro does not skip
  again) and shows "Intro skipped" for about 3 s.
- Fernsy keeps `SupportsMediaControl: false`, so Intro Skipper's server-side auto skip, which
  sends seek commands through the session, can never double-skip with Fernsy's own.

### 8. Prefetch

When the card appears, `JellyfinPlayback` starts loading the next episode's detail
(`store.loadDetail`) and its `PlaybackInfo`, and caches the result keyed by item id for 2
minutes. `make` and the stream start use the cached values when present. Images for the card
come from the episode's Primary image (fallback: series Thumb/Backdrop) through the existing
URL-keyed image cache.

### 9. Settings

`SegmentPreferences` in FernsyCore next to `TrackPreferences`, stored in UserDefaults
(`jellyfin.autoplayNext` Bool, default true; `jellyfin.skipSegments` "button"|"auto"|"never",
default "button"). Per device, not synced: on a TV automatic skipping may be wanted, on a phone
not.

- Rejected: syncing through iCloud like logins. It is a preference of the device and its
  remote, and the existing sync store carries account data, not player preferences.

### 10. One card design

Content and behavior are shared: image (16:9, rounded), "Next Episode" / countdown ring around
Play Now, series, "S2 · E5", title, buttons Play Now + Watch Credits (credits) or Play Now +
Cancel (end of file), or Continue Watching (still watching). Layout follows each platform (Mac
bottom-right material card, Apple TV 640 pt card with focus section, iOS compact card above the
controls). No shared SwiftUI view across targets: the Mac app is a separate target and the tvOS
focus code differs; a shared view would need more conditionals than it saves.

## Risks / Trade-offs

- [False Outro at the end of a non-credits scene] → The rule takes the last block only; Watch
  Credits and Back keep the user in control, and the countdown is 10 s.
- [Card during a post-credits scene] → Blocks ending > 10 s before the end get no countdown.
- [Played mark the user did not want] → Only within the final credits, the same moment Jellyfin
  web and the big services treat as watched.
- [Segments arrive after the credits started (slow server)] → The check runs whenever segments
  arrive; if the position is already inside the block, the card appears at once.
- [Test server has no segment provider] → The fixture episodes get chapters for the fallback
  path; the segment path is tested by unit tests of the rule plus a debug switch
  `JF_TESTSEGMENTS` (DEBUG only) that injects segments for UI tests. Where possible Intro
  Skipper is also installed in the throwaway test container, whose chapter-based analysis turns
  the chapters into real segments.
- [Old servers return 404 for `/MediaSegments`] → Treated as no segments; chapters still work.

## Migration Plan

None. New settings default to today's behavior plus the credits card. Rollback is a revert;
nothing is written to the server except the played mark.

## Open Questions

- Exact chapter name list beyond the ones seen; extend when users report releases with other
  names.

## Notes from implementing

- Item details (`Items/{id}`) already include `Chapters`; `detailFields` (used for grids, not the
  detail) did not need it.
- Chapter fallback, refined while writing the rule: the name must match as a whole (so
  "Opening Credits" never counts), the chapter must lie in the second half of the episode, and
  it reaches the end unless a chapter other than a preview ("Preview", "Next Episode",
  "Vorschau") follows.
- Sample (1.4), read-only from the developer's server on 16 Nov, 126 episodes (the 30 from the
  exploration plus whole seasons of four series): 94 cards with countdown, 31 cards without
  countdown, 1 episode without card (only an intro), 55 skip buttons, no episode with a card
  before its last Outro, none needing the chapter fallback. The 31 without countdown: One Piece
  S1–S2 (Outro ends 33 s before the end; the preview after it is neither a segment nor a named
  chapter), Lucky Luke S1E2 (26 s), Andor S1E12 (43 s: the finale's scene after the credits).
  A larger tolerance that would give One Piece a countdown would also count down over Andor's
  scene, so the 10 s stay; those episodes show the card with Play Now and no countdown.
- The rules of design 4, 6 and 7 are pure types in FernsyCore (`SegmentTracker`,
  `NextCardState`, `AutoplayStreak`), tested with the package (`SegmentTrackerTests`) instead of
  FernsyPlayer tests with a fake position stream; `JellyfinPlayback` only wires them. The
  still-watching count is a static on `JellyfinPlayback` (one player per app) rather than on the
  store or app model.
- `PlaybackInfo` is only requested for transcodes and starts one on the server, so the prefetch
  (design 8) loads the next episode's detail and segments, not its playback information. Direct
  play then starts without any request before the stream.
- Apple TV skip button: not a focus target after all. A focusable button took the remote's moves
  (Left/Right seek), so the player keeps focus and Select skips while the pill shows (spec:
  "while the skip button shows, Select SHALL skip"). Play Now gets focus explicitly when the
  card appears; without it focus went nowhere and the countdown ran out.
- `@Published` sends before the value is set: the credits log line takes the position from the
  publisher, not from `PlaybackProgress`.
- The card is one shared view for Apple TV, iPhone and iPad (`FernsyTV/Player/UpNextViews.swift`)
  and its own on the Mac. Widths were set from screenshots with the German texts ("Jetzt
  abspielen", "Abspann ansehen"): 960 pt on Apple TV, 500 pt on iPhone, 600 pt on iPad.
- The Apple TV/iOS debug MCP server seeks only relatively; its `now_playing` now also reports the
  Jellyfin `item_id` (tests identify the episode by it).
- Mac (3.1): checked with Fernsy Dev against the test Jellyfin through the debug MCP and the log
  (card with countdown at 96 s, prefetch, S01E02 and S01E03 started by the countdown, played
  mark, `now_playing` "playing" with `next.starts_in_seconds`). Window screenshots failed that
  morning (the screen was locked), so the Mac card and skip button were not seen.

## Later fixes

- fix/player-jellyfin-observe (16 Nov): the Apple TV and iOS players first mirrored the card,
  countdown and skip button into `@State` with `onReceive(model.jellyfinPlayback?.$card … ??
  Just(nil))`. A `Just` (and an `@Published` publisher) sends at once on every subscription, and
  SwiftUI subscribes again whenever the view is rebuilt, so every rebuild of the player (IPTV
  films, recordings, live TV on iOS) set state once more. `TVModel` now passes the playback's
  `objectWillChange` on as its own (the playback only publishes on rare changes), and the players
  read `model.jellyfinPlayback` directly. Rejected: `Empty()` instead of `Just(nil)`, which would
  leave stale skip state after a Jellyfin item when an IPTV film plays.
