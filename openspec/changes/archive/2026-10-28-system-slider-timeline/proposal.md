# Proposal

## Why

The live timeline in the Mac player can barely be dragged: its knob and bar are drawn with
`.offset`, which moves only the drawing, so the area that takes the mouse is a thin strip above
the bar. Grabbing the knob does nothing, which feels like moving a layer underneath without
seeking. The custom timelines also look different from the volume slider next to them, whose
system knob turns to glass while dragged. Since macOS 26 the system `Slider` can draw tick
marks, which removes the main reason it was rejected in `redesign-player`.

## What Changes

- The live timeline and the film timeline use the system `Slider` for bar and knob, so they
  look and behave like the volume slider (glass knob while dragging) and take the mouse on the
  knob and anywhere along the bar.
- Show starts on the live timeline become the slider's tick marks; titles above, clock times
  below, the buffer length and the red live dot stay, aligned with the slider's track.
- The film timeline keeps elapsed and remaining time and the hover mark with the time under
  the pointer.
- The film timeline no longer shows the buffered part as a lighter segment (the system track
  has one fill).
- Clock times on the live timeline come from the buffer's own mapping, so marks no longer jump
  for a moment after a seek.
- First task is a spike: if the text cannot be aligned reliably with the system slider, the
  change falls back to the own bar with a glass knob (see design.md), keeping the rest.

Out of scope:
- The Apple TV player (focus-driven, no mouse).
- Seeking behaviour itself (seek on release, release at the end goes live, ±10/±60 buttons and
  keys).
- The volume slider.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `timeshift`: "Rewind and seek in live TV" – the timeline is dragged at its knob or anywhere
  along the bar.
- `playback`: "Transport controls and keyboard" – the same for the film scrub bar.

## Impact

- `Fernsy/Views/PlayerTimeline.swift` (`LiveTimeline`, `FilmTimeline`), possibly
  `Fernsy/Views/PlayerScreen.swift` (`PlayerControls.panel`).
- `PlayerEngine.wallTime(of:)` gets a caller in the timeline; no engine change expected.
- Revises decision 2 ("Rejected: keeping the system `Slider`") of
  `archive/2026-10-24-redesign-player/design.md`.
- Strings: none new expected; any new string needs its German translation.
