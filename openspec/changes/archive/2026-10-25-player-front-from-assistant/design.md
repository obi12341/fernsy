# Design

## Context

`PlayerWindow.show(app)` (in `MCPTools.swift`, used by MCP `play` and Siri's `OpenChannelIntent`
through `FernsyActions.playChannel`) sets the activation policy to regular and opens the player
window through the stored `openWindow`, but returns early when the window is already visible.
`LibraryView` also opens the player on every `nowPlaying` change. Neither orders the window to
the front, and Fernsy is a background app during an external request, so the window ends up
behind the active app's windows.

## Goals / Non-Goals

**Goals:**
- The player is visible in front after an external start, every time.

**Non-Goals:**
- Taking keyboard focus or activating Fernsy.

## Decisions

- **`NSWindow.orderFrontRegardless()`** on the player window, after `deminiaturize` when it is
  minimized. It places the window above other apps' windows without activating the app, and
  macOS does not refuse it (unlike `NSApp.activate()` under cooperative activation since
  macOS 14). Rejected: `NSApp.activate()` + `makeKeyAndOrderFront` (variant B: takes focus and can
  be refused while the user types) and raising the window level (would keep the player above
  other windows after the user switches away).
- **Newly opened window**: `show` sets `PlayerWindow.pendingFront = true` before `openWindow`;
  the player window, when it appears (`PlayerScreen` `onAppear` with its `NSWindow`, found through
  the window identifier), orders itself front regardless and clears the flag. A window that
  is already there is ordered front directly in `show`. Pitfall found in testing: a single
  `orderFrontRegardless()` is undone – SwiftUI orders a new window in after `onAppear`, and
  starting playback reorders an existing window – so both paths repeat it at 0, 0.15 and 0.4 s. Only external starts set the flag; starts
  inside Fernsy keep the normal behavior.
- **PiP**: `show` stays a no-op while PiP runs.

## Risks / Trade-offs

- [The window appears in front while the user is typing elsewhere] → that is the intent of an
  external start; focus is not taken, so typing continues in the user's app.
