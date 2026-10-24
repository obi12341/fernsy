# Proposal

## Why

The player is Fernsy's main experience, but its overlay is plain, and the timeshift bar
says little about where in the program the user is. The redesign in the Claude Design project "Fernsy Redesign" (https://claude.ai/design/p/7e8ce8af-3424-46d0-bc65-69847eaa3c9f),
`Player.dc.html` (variants live, liveEdge, film, pip, loading, buffering, error, tech,
dialog and zap), builds the controls as one glass panel. The timeshift bar shows show
boundaries and titles, and each player state gets a clear card.

## What Changes

- **Overlay**:
  - top and bottom gradients and the traffic lights only while the overlay shows
  - a caption pill top left with logo tile, name, tags and the current show (for films:
    title, year, genre, source)
  - for a recording, a red pill top right "Aufnahme · bis HH:MM"
- **Glass control panel** (bottom, 22 pt radius) for live:
  - **First line:** JETZT with title, time and remaining minutes, and DANACH.
  - **Timeshift bar:** covers the whole buffer, with show boundaries and titles above,
    clock times and "Puffer 2 Std." below, and a red live dot at the end.
  - **Buttons:** channel ⌃/⌄, −10, play/pause, +10 (disabled at the live edge).
  - **Live status:** "−12:34" with a red "ZU LIVE ⇥" when behind, or a red "LIVE" badge at
    the edge.
  - **More controls:** a record button ("Aufnehmen R" / "Aufnahme beenden"), volume, "Ton &
    UT", info (i), PiP and full screen.
- **Film controls**: a scrub bar with elapsed and remaining time, and a hover marker with
  the target time. −60/−10/+10/+60. The audio and subtitle tracks share one menu with
  sections.
- **States**:
  - **Loading:** a large logo tile, a spinner and "… wird geladen …".
  - **Reconnecting:** a centred card "Verbindung wird wiederhergestellt …" with the attempt
    count.
  - **Channel offline:** an error card with the reason ("liegt am Anbieter, nicht an
    deiner Verbindung"), "Erneut versuchen" and "Nächster Sender ↓".
  - **Technical info (⌘I/I):** a glass panel.
  - **No audio:** a toast "Kein Ton auf dieser Spur" with "Tonspur wechseln …".
  - **Recording conflict:** stays the native alert (see the design).
  - **Zap banner:** number, logo, name and tag, current show with progress, Danach, and
    ↑/↓ hints.
- **PiP**: the loading card shows the target's logo tile next to name and show (the blurred
  last picture is kept).
- **Light appearance**: the glass becomes light and the text dark; the red badges stay.

Out of scope:
- Playback engine behaviour (reconnects, timeshift logic), which stays as specified.
- New player features such as a guide inside the player or thumbnails on the scrub bar.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playback`: overlay layout, the combined track menu, the hover marker on the scrub bar,
  and the reconnect, error and no-audio presentation.
- `timeshift`: show boundaries and titles on the bar, and the "−mm:ss · ZU LIVE" / "LIVE"
  presentation.
- `live-tv`: zap banner content, and "Nächster Sender" on the offline error.
- (The recording mark in the player is part of the `playback` overlay requirement.)

## Impact

- `PlayerScreen.swift` (overlay, controls, banners, states), `PictureInPicture.swift`
  (loading card logo).
- `PlayerEngine`: expose the reconnect attempt number and the show boundaries within the
  buffer (EPG for the buffered time span).
- Depends on `redesign-foundation`.
