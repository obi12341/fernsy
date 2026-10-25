# Design

## Context

See proposal.md for why. The library is a SwiftUI `WindowGroup` (`id: "library"`, window
identifiers prefixed "library"), the player a single `Window` ("player"). `PlayerScreen`
already observes `NSWindow.didEnterFullScreenNotification` / `didExitFullScreenNotification`
for its own window (icon state) and makes the window `.fullScreenPrimary` in
`toggleFullScreen`. `MenuBarSupport.showLibrary` and `PlayerWindow.showLibrary` reuse a library
window only when it is visible or minimized; otherwise they open a new one.

## Goals / Non-Goals

**Goals:** activation of Fernsy during full-screen playback lands on the player; nothing is
lost when full screen ends.

**Non-Goals:** different behaviour per activation path; remembering the choice across launches.

## Decisions

- **Hide with `orderOut`, remember the windows.** A small `LibraryWindows` helper (main actor)
  keeps weak references to the library windows it hid. On the player's
  `didEnterFullScreen` it orders out every visible, non-minimized library window. On
  `didExitFullScreen` and when the player window closes, it orders them back with
  `orderFront` *behind the player* (`order(.below, relativeTo: player)`), so focus stays on
  the player. Rejected: closing the library (loses its state: section, scroll position, search),
  and minimizing (animates into the Dock and leaves a Dock tile).
  Minimized library windows are left alone: they are not on the desktop Space anyway.
- **Hidden windows count as available.** `MenuBarSupport.showLibrary` and
  `PlayerWindow.showLibrary` first ask `LibraryWindows` for a hidden window and show that
  (which ends the hiding for it), before falling back to opening a new one.
- **Default when leaving full screen: restore right away.** The user did not pick between
  "restore on leaving full screen" and "restore only when the player closes"; restoring on
  leaving full screen returns to the exact state before full screen, which is the least
  surprising. Recorded here so it can be revisited.
- Rejected: forcing the player to the front on every activation (variant B). Fernsy cannot tell
  ⌘-Tab from a click on the library window, so a deliberate click would be pulled into full
  screen.

## Risks / Trade-offs

- [Quit while hidden] → SwiftUI's window restoration may remember the library as closed; the
  library `WindowGroup` opens a window at launch anyway. Verified in the tasks.
- [Several library windows] → all visible ones are hidden and restored in their order.
