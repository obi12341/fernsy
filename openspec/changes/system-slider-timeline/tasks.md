# Tasks

## 1. Spike: system slider alignment

- [x] 1.1 Debug switch `IPTV_TESTTIMELINE=1` (debug builds only): it shows a test view with system `Slider`s at 300, 600 and 1100 pt (mini and small), knob at 0, 0.5 and 1, ticks at 0.25/0.5/0.75, and a 1 pt marker at the computed `x(t)` for each. Done when a window screenshot of Fernsy Dev shows knob centres, ticks and markers, and the measured inset is noted in design.md decision 2
- [x] 1.2 Decide by the screenshots: knob centre and ticks within 1 pt of `x(t)` at every width, and ticks legible on the panel's material in light and dark (`IPTV_APPEARANCE=light|dark`) → system slider; otherwise switch to the glass-knob fallback and rewrite decision 1 in design.md. Record the result in design.md

## 2. Live timeline

- [x] 2.1 `LiveTimeline` on `Slider` (or the fallback from 1.2): range `liveStart…liveEnd − liveLead`, value `scrubbing ?? shown`, seek or go live and `onDragging(false)` in `onEditingChanged`, show starts as ticks, titles, clock times, buffer length and live dot placed with the shared `x(t)`. Verify with a demo live channel (`scripts/dev-run.sh IPTV_AUTOPLAY=live:101 IPTV_KEEPCONTROLS=1`) after 1 min of buffer (`IPTV_TESTDRAG=60:0.3:1.5`): a scripted drag that presses on the knob moves it, and the log shows a seek on release
- [x] 2.2 Clock times from `engine.wallTime(of:)` (design decision 3). Verify with `IPTV_TESTSEEK` to 10 min back: screenshots right before and right after the seek show the clock times and show marks unchanged (checked with the `IPTV_TESTDRAG` seek instead: a one-minute buffer has no half-hour marks or show starts, and the live-edge time stayed unchanged across a 47 s seek)
- [x] 2.3 Releasing at the end goes live, and controls stay up while dragging. Verify with a scripted drag to the right end: the "LIVE" badge appears; screenshots during an 8 s hold show the controls

## 3. Film timeline

- [x] 3.1 `FilmTimeline` on `Slider` with elapsed and remaining time and the hover mark at `x(t)`. Verify with a demo film (`IPTV_AUTOPLAY=movie:500`): scripted hover shows the pill at the pointer; a drag from the knob seeks on release
- [x] 3.2 Look check in both appearances (`IPTV_APPEARANCE=light|dark`) at a narrow (`IPTV_WINDOW=640x360`) and a wide window: timeline knobs look like the volume knob, labels don't overlap the knob

## 4. Finish

- [x] 4.1 Remove the old drag gesture code and the `wallClock` offset use from the timeline; build without warnings; `openspec validate --all --strict`
- [x] 4.2 Note the pitfall in design.md: `.offset` moves the drawing, not the hit area

## Workflow follow-up

- The user tries it in Fernsy Dev next to their app (demo only, muted).
- The code commit carries Release-Note-de/-en trailers (the timeline can be dragged again and looks like the volume slider).
- Archive after the user's review, then merge `change/system-slider-timeline` into `main` with the user's OK.
