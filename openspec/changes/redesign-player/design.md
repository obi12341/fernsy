# Design

## Context

`PlayerScreen.swift` (about 1,200 lines) holds the player window:

- **`PlayerControls`:** a top bar with title, LIVE/ZEITVERSETZT, REC and EPG, plus a bottom
  `ultraThinMaterial` panel with system sliders. The panel has a timeshift slider, wall
  clock and "LIVE/−mm:ss", or a film slider, then buttons: zap, ±10, play, record, audio
  and subtitle menus, PiP, info, volume and full screen.
- **`ChannelOSD`:** the zap banner. It loads a short EPG on its own.
- **`statusOverlay`:** a spinner with "Verbinde …" or "Verbindung wird wiederhergestellt …",
  or a failure card with Retry.
- **`AudioStatusBadge`, `StatsOverlay`, `NextEpisodeOverlay`.**

The PiP loading card (`PictureInPictureLoadingCard`) draws spinner and title into pixel
buffers. `PlaybackProgress` provides `position`, `liveStart`/`liveEnd` (buffer time),
`wallClock` (clock time of `position`) and `followsLive`. The screen keeps `epg: [EPGEntry]`
for the playing channel.

**Design source:** Claude Design "Fernsy Redesign", `Player.dc.html`, with the variants live,
liveEdge, film, pip, loading, buffering, error, tech, dialog and zap. Shared parts come from
`redesign-foundation`.

## Goals / Non-Goals

**Goals:**
- One calm glass panel.
- A timeshift bar that tells where in the program the user is.
- Clear state cards.
- A richer zap banner.

**Non-Goals:**
- Engine behaviour: reconnects and timeshift logic stay as specified.
- New features: a guide in the player, or thumbnails.
- A custom recording-conflict dialog. It stays the native `NSAlert`: it can appear while
  the player window is hidden, in PiP or with no window open, and only the system alert
  works in all three.

## Decisions

### 1. Structure

`PlayerControls` is rebuilt as follows, all in `PlayerScreen.swift` plus a new
`PlayerTimeline.swift` for the two bars:
- `CaptionPill` (top left)
- `RecordingPill` (top right)
- top and bottom gradients
- `ControlPanel` (bottom glass, radius 22, 40 pt side margins, max 1100 wide)

The panel uses `.regularMaterial` and system label colours, so it follows the appearance:
dark glass with white text, or light glass with dark text. State cards and the zap banner
stay dark, because they sit on the video.

### 2. Timeshift bar

`LiveTimeline` maps buffer time to x over `liveStart…liveEnd − liveLead` (the playable
range).

**Clock times:** for a buffer time `t`, the clock time is `wallClock + (t − position)`. Half-
hour ticks are labelled below, "Puffer N Min./Std." at the left, and the live-edge clock time
at the right.

**Show boundaries:** EPG entries whose start lies inside the range draw a 2 pt notch with
the title above; the title of the current show is semibold. A red dot marks the live end.
The played part is solid and the buffered remainder is translucent.

**Interaction:** dragging the knob or clicking the bar seeks; releasing within 1 s of the
end goes live. The drag reporting (`onDragging`) is kept, so the auto-hide still pauses.

Rejected: keeping the system `Slider`. It cannot draw notches, titles or a two-tone track.

### 3. Film scrub bar

`FilmTimeline` shows elapsed time, the bar (played and buffered) and remaining time. While
hovering, a marker and a pill show the time at the pointer. Click or drag seeks. The
buttons are −60, −10, play/pause, +10 and +60.

### 4. Live first line and buttons

**First line** (live only): "JETZT title · HH:MM–HH:MM · noch N Min." on the left,
"DANACH HH:MM title" on the right, from `epg`.

**Buttons, from left to right:**
1. ⌃/⌄ (live only), a divider
2. the ±10 group around play/pause (42 pt circle)
3. the live status:
   - when behind, a pill "−12:34" with a red "ZU LIVE ⇥" part that goes live
   - when following, a red "● LIVE" badge
4. a spacer
5. the record capsule: "Aufnehmen R", or red "Aufnahme beenden"
6. volume
7. "Ton & UT": one menu with the sections Tonspur and Untertitel
8. info, PiP and full screen as round 32 pt buttons

### 5. Caption and recording pill

**Caption pill:** a glass capsule top left.
- Live: logo tile (48), cleaned name, tags, then "title · HH:MM–HH:MM" below.
- Film: a play glyph tile, title, and the subtitle (year, genre, source).

It is hidden while the zap banner is shown, the same way the title is hidden today.

**Recording pill:** red, top right, "Aufnahme · bis HH:MM", where the end is the
recording's `recordEnd`.

### 6. State cards

- **Loading:** a large logo tile (150) for live channels, a spinner, and "<title> wird
  geladen …".
- **Reconnecting** (`isReconnecting` or a buffering restart): a glass card "Verbindung wird
  wiederhergestellt …". When the engine restarts the stream, `reconnectAttempt` (now
  published) adds "Versuch n von 8". HTTP-level reconnects inside the tuner are too short
  to show a count.
- **Failure:** a glass card with an amber "!".
  - Offline at the provider (the message equals `PlayerError.offline`): the title "Sender
    ist beim Anbieter offline" and the text "<Name> liefert gerade kein Bild. Das liegt am
    Anbieter, nicht an deiner Verbindung.", plus "Erneut versuchen" and, for live, "Nächster
    Sender ↓" (zap +1).
  - Other errors: the message as the title and only "Erneut versuchen".

### 7. Zap banner

`ChannelOSD` is rebuilt as follows:
- the number in light weight
- the logo tile (66)
- the tagged name and "title · HH:MM–HH:MM"
- a progress bar
- a footer "Danach HH:MM title" with ↑ ↓ key caps

It uses the same dark glass. The banner already loads two EPG entries, which give now and
next.

### 8. PiP loading card with logo

`PictureInPictureLoadingCard.start` takes an optional logo `CGImage`, taken from
`ImagePipeline.cached` at the sizes `LogoTile` requests. It draws a graphite rounded tile
with the logo, or the initials, left of the title. The title moves right accordingly, and
the spinner stays above.

## Risks / Trade-offs

- **Custom timelines** need their own accessibility. They get an `accessibilityValue` with
  the position and adjustable actions for ±10 s.
- **The light glass** over bright video is less contrasty than dark glass. The design source
  accepts this; the bottom gradient helps.
