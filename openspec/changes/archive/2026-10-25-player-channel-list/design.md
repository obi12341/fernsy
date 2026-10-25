# Design

## Context

`PlayerScreen` (`Fernsy/Views/PlayerScreen.swift`) layers overlays in a `ZStack` over the
video:
- the status cards;
- `ChannelOSD`, the zap banner, at the top left;
- `PlayerControls`, the glass panel at the bottom, which hides after 3 s;
- `StatsOverlay`, at the top right.

Keys arrive through `handleKey(_:)` (an `NSEvent` monitor). For live TV, ↑/↓ and Page Up/Down
call `zap(_:)`, which shows the banner and tunes after 400 ms of quiet. Zapping walks
`AppModel.zapList(categoryId:)`: the visible channels of the category the channel was started
from, which `PlayItem.Kind.live(id, categoryId)` carries.

`app.play(channel)` takes the category along. It already asks when a recording holds the only
connection. In the library, `ChannelRow` has number, logo, `TaggedName`, `NowNextLine` and
marks, and loads the programme with `.task { app.epg.load }`.

The design brief has no player channel list. The style follows the existing player overlays:
materials, rounded panels, `Theme` colours, `StatusBadge` and `LogoTile`.

## Goals / Non-Goals

**Goals:**
- See what is on now and switch without leaving the player, also in full screen.
- Mouse and keyboard work equally well.
- The same channel order and behaviour as zapping.

**Non-Goals:**
- A filter or search field.
- The programme grid in the player.
- Films and series.
- Picture in Picture.
- Changing ↑/↓ while the list is closed.

## Decisions

### 1. An overlay panel from the left, not a sidebar

The panel is 340 pt wide (at most 45 % of the window) and spans the height between a
top inset and the control panel. It uses a `.regularMaterial` rounded rectangle (radius 18),
like `PlayerControls`, and slides in from the left edge.

Found during verification: with the timeline and the programme line, the control panel is
about 190 pt high, so the panel keeps 200 pt clear at the bottom while the controls show (24 pt
otherwise). An inset of 120 pt let the panel cover the left part of the controls.

The picture keeps its size and position. The zap banner sits at the top left too, so while
the list is open it moves next to the panel. The list already shows the same information.

Rejected:
- **A sidebar that shrinks the video:** the picture jumps on every open and close, and in
  full screen the video loses its 16:9 fit.
- **A bottom strip of channel tiles, like many TV boxes:** it shows few channels with little
  text, and it collides with the control panel and the subtitles.
- **A separate window:** it does not work in full screen, and it splits focus.

### 2. Rows tuned for the player

`PlayerChannelRow` has the same parts as `ChannelRow`:
- number, a 40 pt `LogoTile` and `TaggedName`;
- the current show in one line, with a `ProgressBar` below it;
- marks from `StatusBadge`: "In Player" (accent background on the row), REC and offline.

The next show is left out, because the panel is narrow. Rows load their programme like
`ChannelRow` (`.task(id:)` → `app.epg.load`). The `List` only creates visible rows, so the
download limits apply as in the library.

`ChannelRow` itself is not reused. It contains the favourite star and the edit-mode parts,
and its layout is meant for the wide library list.

### 3. The category menu at the top

The header shows the category name as a `Menu`, with these entries:
- "Favoriten" (`__favorites`);
- "Zuletzt gesehen" (`__recent`);
- a divider;
- the visible live categories.

The list starts with the category of the channel playing. Picking another category only
changes the list. Tuning a channel plays it with `app.play(channel)`. As in the library,
that uses the channel's own category, so afterwards ↑/↓ zaps through that category, also
for a channel picked from "Favoriten".

Rejected: making "Favoriten" or "Zuletzt gesehen" the zap list. They only exist as views
today; `play` and `zapList` know only real categories. Starting a favourite from the library
already zaps through its own category, and the player should not behave differently.

### 4. Keyboard and focus

While the list is open, `handleKey` sends keys to it first:

| Key | Action |
|---|---|
| ↑/↓ | move the highlight; keeps it visible with `ScrollViewReader` |
| Page Up/Down | move the highlight by a page |
| Return | tune the highlighted channel |
| L or Esc | close the list |

Space, M, F, R and the other keys keep their meaning. The highlight starts on the channel
playing.

Rejected: letting ↑/↓ zap while the list is open. The list would jump and tune on every key
press, so browsing would not work.

### 5. Closing and auto-hide

The list closes:
- with L or Esc;
- with a click on the picture outside the panel;
- after 10 s without any interaction with the list (hover, scrolling, keys).

Mouse movement over the picture keeps the controls up but does not keep the list open. Tuning
a channel restarts the 10 s. The control panel follows its own 3 s rule. The list stays open
while the controls hide, because the button is not needed to use it.

### 6. Testing without input on the user's screen

`IPTV_TESTCHANNELLIST=<s>[:<keys>]` opens the list after `<s>` seconds. It optionally feeds
the given key names (`down`, `up`, `return`, `esc`) straight into the screen's handler, one
per second. No events are posted to the system. The run uses the demo server with
`IPTV_AUTOPLAY=live:<id>`, and screenshots are taken of the player window only.

## Risks / Trade-offs

- **[The panel covers part of the picture]** → It is the left 340 pt, closed with one key,
  and it hides itself after 10 s.
- **[The programme loads for many channels when a long list is scrolled]** → The existing
  `EPGStore` limits apply (two tables at a time, cancellation), as in the library.
- **[A conflict with the parallel change `live-now-next-follows-clock`]** → Both touch the
  minute redraw of rows. Whichever is merged second reuses the other's clock. The task list
  checks for this.
