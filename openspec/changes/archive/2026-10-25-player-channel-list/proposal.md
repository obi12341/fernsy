# Proposal

## Why

In the player, the user can only step through channels one at a time with ↑/↓. To find out
what is on elsewhere, or to jump further, they have to go back to the library window. A
channel list in the player, showing what is on now, makes switching possible without leaving
the picture. That matters most in full screen.

## What Changes

- **Channel list as an overlay.** A panel slides in over the picture from the left edge, in
  the player's glass style. The picture keeps running and stays where it is; the panel does
  not shrink it.
- **Opening and closing.** A new button in the control panel ("Senderliste", L) opens it;
  it is shown only for live TV. It closes with:
  - L or Esc (Esc first closes the list, then leaves full screen);
  - a click on the picture;
  - 10 s without interaction.
- **Content.** The list shows the channels of the category being zapped through, in zap
  order and without hidden channels. Each row has:
  - number, logo and name with tags;
  - the current show with its progress;
  - marks for "in player", recording (REC) and offline.

  A menu at the top switches the category: Favourites, Recently Watched and the categories.
  On opening, the list scrolls to the channel playing now.
- **Switching.** A click on a row tunes that channel, with the usual banner and the usual
  question when a recording needs the connection. The list stays open. ↑/↓ moves the
  highlight in the list instead of zapping, and Return tunes the highlighted row. After
  closing, ↑/↓ zaps through the tuned channel's own category, as when it is started from
  the library, also when it was picked from "Favoriten".

Out of scope:
- a filter or search field in the list (the library search exists);
- the full programme grid in the player;
- the film and series player;
- Picture in Picture.

## Capabilities

### New Capabilities
- (none)

### Modified Capabilities
- `live-tv`: new requirement "Channel list in the player" (opening, content, switching,
  keyboard).
- `playback`: "Player overlay" gets the channel list button for live TV.

## Impact

- New `Fernsy/Views/PlayerChannelList.swift`: the panel, rows and category menu.
- `Fernsy/Views/PlayerScreen.swift`:
  - state for the open list;
  - keys L, ↑/↓, Return and Esc while it is open;
  - the button in `PlayerControls`;
  - auto-hide;
  - the panel kept clear of the control panel.
- `AppModel`: no new logic. The list uses `zapList(categoryId:)` and the library's favourite
  and recent lists, and tunes with `play(_:)`.
- `EPGStore`: rows load their programme the same way as in the channel list.
- `Localizable.xcstrings`, README (debug switch).
- If `live-now-next-follows-clock` is merged first, the rows reuse its minute clock.
  Otherwise they bring their own `TimelineView(.everyMinute)`.
