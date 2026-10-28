# Design

## Context

`LiveTimeline` and `FilmTimeline` (`Fernsy/Views/PlayerTimeline.swift`) draw bar, knob, notches
and labels themselves (decision 2 of `archive/2026-10-24-redesign-player`). In `LiveTimeline`,
every part is placed with `.offset`, which moves only the drawing. The `ZStack` therefore gets
the height of its tallest part before offsetting (the 14 pt knob) at the top. Its
`.contentShape(Rectangle())`, and so the `DragGesture`, covers only that strip above the bar.
`FilmTimeline` does not have this bug: it gives its `ZStack` `.frame(height:)` before the
content shape.

Clock times use `wall(t) = wallClock + (t − position)`. After a seek, `position` changes at
once while `wallClock` follows with the next position event. For that moment every mark is off
by the seek distance. `PlayerEngine.wallTime(of:)` reads the buffer directly for exactly this
reason (see its doc comment).

The deployment target is macOS 27, so the macOS 26 `Slider` API is available: `ticks:`
(`SliderTick`), `neutralValue`, `enabledBounds`, plus the Liquid Glass knob the volume slider
already shows.

## Goals / Non-Goals

**Goals:**
- One slider look in the panel: timelines and volume share the system knob.
- The grab area is the system's, not something we lay out by hand.
- Labels and notches line up with the knob at every panel width.

**Non-Goals:**
- Changing when seeks happen. Seek on release and "release at the end goes live" stay; the
  `onDragging` reporting for the auto-hide stays.

## Decisions

### 1. System `Slider` for bar and knob (revises redesign-player decision 2)

Both timelines use `Slider` for the bar and knob. The binding writes only the local
`scrubbing` value. `onEditingChanged(false)` seeks (or goes live within 1 s of the end) and
reports `onDragging`, as the drag gesture did before. The live slider's range is the playable
range `liveStart…liveEnd − liveLead`. Its value is `scrubbing ?? shown`, so the range growing
with live does not move the knob while dragging.

Show starts become `ticks:` on the live slider. Titles above, clock times and the buffer length
below, and the red live dot are views around the slider.

New reasons against the old rejection ("cannot draw notches, titles or a two-tone track"):
- Notches: the slider draws them since macOS 26.
- Titles: they were always separate text, not part of the bar.
- Two-tone track: live needs none (everything after the knob is buffered). Only the film's
  buffered segment is lost; for IPTV and Jellyfin films it is rarely informative.
- The hand-made hit area failed unnoticed (see Context). The system slider removes that class
  of bug and brings keyboard and VoiceOver handling with it.

Rejected:
- Keeping the custom bar and fixing only the hit area (one `.frame` line): fixes the bug, but
  the panel keeps two slider looks.
- An own bar with a `.glassEffect()` knob: lines up exactly, but imitates the system knob. It
  will drift when Apple changes it, and hit area and accessibility stay ours. This is the
  fallback if decision 2 fails.

### 2. Lining up labels with the knob

The system slider runs the knob's centre inside the track with an inset (about half the knob
width). Labels use one mapping `x(t) = inset + fraction(t) · (width − 2 · inset)`. The inset is
measured in the spike rather than guessed. The spike lays out sliders at 300, 600 and 1100 pt
with the knob at 0, 0.5 and 1, then compares the knob centre with `x(t)` in screenshots. It
also covers tick positions (they must match `x(t)` too) and the mini/small control sizes. The
volume slider is `.mini`; the timelines likely want `.small`.

If the knob and `x(t)` differ by more than 1 pt at any width, or the ticks cannot be styled
legibly on the glass panel, implement the rejected glass-knob fallback from decision 1 instead,
and record the spike result here.

**Spike result (macOS 27.2, `IPTV_TESTTIMELINE`):** the inset is half the knob width and does
not depend on the slider's width. It is 4.25 pt for `.mini` (knob 8 × 15 pt) and 5.25 pt for
`.small` (10 × 17 pt), measured from window screenshots at 300, 600 and 1100 pt with the knob
at 0, 0.5 and 1. The knob centre lies within 0.5 pt of `x(t)` everywhere. The slider places
its tick dots by the same mapping (below the track, small grey dots, legible in light and
dark). So the system slider stays. The timelines use `.small`: the larger knob is easier to
grab, and the glass look while dragging is the same as the `.mini` volume slider.

### 3. Clock times from the buffer

`LiveTimeline` gets a `wallTime: (Double) -> Date?` closure, backed by `engine.wallTime(of:)`,
for the range ends. Ticks and show marks are placed from those two ends. The `wallClock` offset
is only a fallback when the buffer has no entry. This also follows discontinuities in the
buffer (reconnects) at the ends instead of extrapolating from the current position.

### 4. Film hover mark

The hover mark and time pill stay as an overlay over the slider. They use the same `x(t)`
mapping as decision 2, so the pill points at the spot a click would seek to.

## Risks / Trade-offs

- [The inset changes in a future macOS] → it lives in one constant. The spike's screenshot
  check becomes a debug switch (`IPTV_TESTTIMELINE`) that can be rerun.
- [Many show starts in a 60-minute buffer crowd the ticks] → at most a few per hour.
  Titles already truncate to the space before the next start.
- [The system slider sends a value on click without a drag] → the same as today: a click seeks
  on release.
- [Film loses the buffered segment] → accepted (decision 1).

## Pitfalls

- `.offset` moves only the drawing. Layout, `contentShape` and hit testing stay at the
  unoffset frame. A control assembled from offset parts takes the mouse somewhere other than
  where it is drawn. That was the cause of the live timeline that could not be dragged. Place
  interactive parts by layout (stacks, frames), and keep offsets for text with
  `allowsHitTesting(false)`.
- macOS draws a system slider's filled part in the tint only in the key window; in an inactive
  window it is grey (the volume slider does the same). Accepted.
- SwiftUI hover (`onContinuousHover`) follows the real pointer. Mouse events posted into the
  app's queue (`IPTV_TESTDRAG`) drive the slider, but they do not trigger the film's hover mark.

## Migration Plan

UI only, no data. Rollback is reverting the commit.
