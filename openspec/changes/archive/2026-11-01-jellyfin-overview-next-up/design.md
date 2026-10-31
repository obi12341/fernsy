# Design

## Context

See proposal.md. Start shows Next Up from `JellyfinStore.nextUp`, built into `LibraryEntry`s by
`StartBuilder.nextUp()` (series name, `episodeLine`, backdrop or poster). The Übersicht on each
platform draws Weiterschauen straight from `JellyfinStore.resume`:
- Apple TV (`JellyfinOverviewPage`) and iOS (`JellyfinSearchViews`) as a `CardRow` of `WideCard`s
  that call `model.play(.jellyfin(item))`.
- The Mac (`JellyfinOverviewView`) as a `PagingCarousel` of `JellyfinWideCard`s with a context
  menu (item menu, "Open Series").

## Goals / Non-Goals

**Goals:**
- One source for the row on Start and in Übersicht: `JellyfinStore.nextUp`.
- The row looks and behaves like Weiterschauen next to it on each platform.

**Non-Goals:**
- New data from the server or a second Next Up request.

## Decisions

### 1. Draw the row like Weiterschauen on each platform, from `jellyfin.nextUp`

Each Übersicht adds a second row of the same kind right after Weiterschauen, iterating
`store.nextUp` instead of `store.resume`, without a progress bar (the episodes have not
started). Selecting plays the episode as Weiterschauen does. On the Mac it gets the same context
menu, including "Open Series".

Rejected: reusing Start's `LibraryEntry` rows (`StartBuilder.nextUp()`) in Übersicht. Übersicht's
rows work on `JFItem`s with their own cards and menus; going through `LibraryEntry` would give
this one row a different card and lose the Mac's context menu.

### 2. Refresh comes with the store

`JellyfinStore` is observed by all three Übersichten, and `nextUp` changes with
`refreshHome()` (after playback, `refreshAfterPlayback`), so the row needs no refresh of its own.

## Risks / Trade-offs

- [Two rows of wide cards one after the other] → Both are short (the server returns a handful),
  and the titles tell them apart; Start has the same pair.
