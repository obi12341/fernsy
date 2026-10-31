# Design

## Context

See proposal.md for the motivation. Current state on Apple TV:

- One `PlayerEngine` (`TVModel.engine`) drives the full-screen players (`PlayerScreen`,
  `VODPlayerScreen`, the recordings player) and the Live TV preview pane. The preview hands its
  running connection to the full-screen player (`TVModel.play(_ channel:)`).
- `PlaybackSession` decodes with FFmpeg (VideoToolbox), deinterlaces interlaced TV to double
  rate (`yadif_videotoolbox`, CPU `bwdif` fallback) and enqueues `CVPixelBuffer`s into an
  `AVSampleBufferDisplayLayer`. Dolby Vision goes through `DVDecoder`, which has its own
  `CMVideoFormatDescription`. Profile 7, and profile 8 without a Dolby Vision decoder, play the
  HDR10 base layer.
- The session knows the stream's `avg_frame_rate`/`r_frame_rate` when it opens the stream
  (`PlaybackSession.swift` near line 1146). The clock starts in the preroll gate
  (`sync.setRate(…)` once audio and video are ready, near line 1689).
- tvOS switches the TV only if the app sets `UIWindow.avDisplayManager.preferredDisplayCriteria`
  and the user turned on "Match Content" (`isDisplayCriteriaMatchingEnabled`). For sample-buffer
  pipelines the criteria come from `AVDisplayCriteria(refreshRate:formatDescription:)`. The
  manager's `isDisplayModeSwitchInProgress` is key-value observable. Setting `nil` hands the
  mode back to the system.

## Goals / Non-Goals

**Goals:**
- Ask for exactly what the layer shows, as soon as the first frame is decoded.
- No extra black pictures: one switch into a film, one back, none between items of the same kind.
- Keep the logic that decides what to ask for (rate, range, "is it different?") free of UIKit,
  so it is unit-tested on the Mac.

**Non-Goals:**
- Reading or showing the TV's current mode, or warning when "Match Content" is off.
- Choosing a different decoding path because of the TV's capabilities.

## Decisions

### 1. Rate and range come from the decoded output, not from measurement

The session publishes a `DisplayFormat` when the first video frame is decoded: the frame rate
(the stream's `avg_frame_rate`, else `r_frame_rate`, doubled when the deinterlacer runs at 2×)
and the format description of what is enqueued (`CMVideoFormatDescriptionCreateForImageBuffer`
of the first pixel buffer, which carries colour primaries and transfer function, or
`DVDecoder`'s Dolby Vision format description). For HDR10 shown from a Dolby Vision stream this
naturally is the HDR10 pixel buffer's description.

Rejected: the measured `stats.frameRate` from the technical info. It needs seconds of playback,
jitters, and would switch the TV late, during the film.

Rejected: frame rate from the container only, without the deinterlacer's doubling: 25 Hz for
1080i50 would make the TV show the doubled 50 fps picture at 25 Hz and drop every second frame.

Frame rates are snapped to the standard rates (23.976, 24, 25, 29.97, 30, 50, 59.94, 60) when
within 0.5 %, so a stream declaring 25.02 fps does not ask for an odd mode. A stream without a
usable rate (0, or above 120) asks for the dynamic range only (`refreshRate` 0).

### 2. A TV-side controller owns the request

`DisplayModeController` in `FernsyTV` (one per app, held by `TVModel`) watches the engine's
`DisplayFormat`, whether a full-screen player is showing (not the preview: `previewing == nil`
and a player screen is up), and the setting. It finds the key window's `avDisplayManager` and
sets or clears `preferredDisplayCriteria`. The decision itself lives in a plain value type
(`DisplayModeRequest` in `FernsyPlayer`: from a `DisplayFormat` to snapped rate and a range key
of transfer function + primaries + Dolby Vision) with `==`, so "ask again?" is a comparison that
tests cover.

Rejected: setting the criteria inside `PlayerEngine`. The engine is shared with the Mac and iOS
apps, which have no `avDisplayManager`, and it does not know whether it is in the preview or
full screen.

### 3. Hand the mode back only after a grace period

Closing the player clears the request after 2 s, unless another item starts in that time.
Episode autoplay, "next episode", zapping through the channel strip and moving from one
Continue Watching item to another stop and start the engine in quick succession; clearing at
once would switch the TV back and forth.

Rejected: clearing immediately on `stop()`: two extra switches (each 1–3 s black) between
episodes of a series.

### 4. Hold the start, never pause a running picture

`PlayerEngine` gets a start gate that the preroll gate in `PlaybackSession` also waits for (in
addition to audio and video being ready). The controller closes the gate when it sets new
criteria for an item that has not started, waits up to 300 ms for
`isDisplayModeSwitchInProgress` to become true (tvOS does not switch when the TV is already in
that mode), then until it is false, and opens the gate; at most 5 s in all. With the setting
off, matching off in tvOS, the preview, or unchanged criteria the gate stays open, so start-up
time does not change.

A running picture (the preview going full screen, a live channel whose format changes
mid-stream) is never held: live keeps its connection and the TV shows black for the switch.

Rejected: seeking back by the switch's length after it ends. Live streams cannot seek back
without timeshift, and VOD would load twice.

Rejected: delaying the full-screen player until the switch ends. The user would look at the
old screen for seconds with no feedback.

### 5. One switch per account, per Apple TV

Two keys in `UserDefaults` (`@AppStorage`): `player.matchDisplayMode.iptv`, default `false`,
and `player.matchDisplayMode.jellyfin`, default `true`. The rows sit in Settings › IPTV Account
and Settings › Jellyfin Server, each with the note that tvOS only switches when "Match Content"
is on in the Apple TV's settings. Fernsy has one account of each kind at a time, so a key per
kind is a key per account. The IPTV switch covers everything that comes from the IPTV account:
live channels, catch-up, films, series, local recordings and cloud recordings (they are
recordings of its channels). Signing out keeps the choice for the next account of that kind.

The user decided this after trying a single switch on the real Apple TV: switching for every
zap gets in the way while watching TV, but is wanted for films from Jellyfin. The IPTV account
is mostly live TV, so it starts off; Jellyfin is films and series, so it starts on.

Rejected: one switch for everything (the first version, under Settings › Playback). It could
only turn zapping and films on or off together.

Rejected: a switch per content kind (live TV versus films and series). The user chose per
account; IPTV films then follow the IPTV switch.

Rejected: syncing the switches through iCloud. A Mac or a second Apple TV on another TV has
nothing to do with them.

### 6. Mac, iPad and iPhone stay as they are

- macOS: no API asks the system for a mode for content. `CGDisplaySetDisplayMode` would change
  the user's display configuration for all apps (and the menu bar, other windows), needs
  restoring after crashes, and has App Review risk. HDR and Dolby Vision already show in HDR
  through EDR (playback spec "Dolby Vision").
- iPadOS/iOS: `AVDisplayManager` is tvOS/visionOS only. ProMotion chooses the panel rate for
  video layers itself; an external display over HDMI or AirPlay is driven by the system.

Revisit only if Apple adds a content-matching API on these platforms.

## Risks / Trade-offs

- [The simulator never switches modes] → The controller logs every request and release
  (`AppLog` category player: "display mode: 23.976 Hz HDR10 / released / unchanged"); the
  simulator UI test checks the setting and the logged request on the demo server, the real
  switch is checked with the user on "Apple TV WZ".
- [`isDisplayModeSwitchInProgress` does not turn true within 300 ms on a slow TV] → The start
  is then not held and up to a second of the start is lost in black, as today with AVPlayer
  apps that do not wait. The 300 ms is tuned on the real Apple TV.
- [A stream declares a wrong frame rate] → Snapping covers small errors; a grossly wrong rate
  gives the wrong mode until the player closes. Acceptable: the same stream judders today.
- [Zapping between 50 Hz and 60 Hz channels switches each time] → That is why the IPTV
  account's switch starts off; users who want it turn it on.

## Migration Plan

New setting with a default; nothing to migrate. Rollback is turning the setting off or
removing the controller.

## As built

- AVKit adds `avDisplayManager` to `UIWindow`. The first device build used it only through
  that property, so the linker dropped the unused AVKit and the property did not exist at run
  time: the app logged "no display manager" on the real Apple TV, too. A class reference to
  `AVDisplayManager` keeps AVKit linked.
- On "Apple TV WZ" (2026-10-31): a 23.976 fps HDR10 film and a 50 Hz channel each switched the
  TV in 2.9 s. tvOS began the switch within the 300 ms wait, and the item started right after
  the switch ("switched in 2.90 s", then "started"). Zapping through four 50 Hz channels logged
  "unchanged" and did not switch; closing the player released the mode.
- The tvOS simulator's `UIWindow` has no `avDisplayManager`: calling it crashes with an
  unrecognized selector. The controller checks `responds(to:)` first and, without a manager,
  only logs the request ("… (no display manager)"), which the UI tests read.
- The session gives up holding after 8 s of preroll on its own, so a controller that never
  releases (an item without a first frame) cannot keep an item from starting.
- The engine test plays `website/assets/fernsy-video.mp4`. `FileByteSource` now treats only
  `.ts` files as MPEG-TS and lets FFmpeg probe any other file; recordings are always `.ts`.
