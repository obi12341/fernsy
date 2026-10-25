# Design

## Context

- **The history:** `AppModel.recentChannels` (channel ids, newest first, at most 20) is
  stored in UserDefaults (`live.recent`). `noteRecent` adds a channel when it is played. Test
  runs without the keychain keep it in memory, because they share the installed app's
  defaults.
- **The pinned entry:** `filteredChannels(categoryID:query:)` builds every Live TV list,
  including the pinned entry "Zuletzt gesehen" (`recentChannelsID`). The guide and the count
  in the category column use the same function.
  - While `showAdult` is off, that function already drops channels with `isAdult` and
    channels in categories detected as adult (`isAdultCategory`).
  - While it is on, nothing is dropped, so adult channels show up in "Zuletzt gesehen".
- **The setting:** `showAdult` ("Erwachsenen-Kategorien anzeigen") is a published
  `AppModel` property stored in UserDefaults (`library.showAdult`). It is shown in
  `YouthProtectionSettings` (`LoginView.swift`).
- **The menu:** `ChannelMenu` (`ChannelDetailPane.swift`) is the context menu of the list
  rows and the detail pane's "…" menu.
- **The demo server** has no adult channels or categories.

## Goals / Non-Goals

**Goals:**
- Adult channels stay out of "Zuletzt gesehen" by default, everywhere that entry appears.
- Single channels can be removed from the history.
- Tests on the demo server without touching the installed app's settings.

**Non-Goals:**
- Clearing the whole history; a history for films, series or Jellyfin.
- Changing adult detection.

## Decisions

### 1. A display filter, not a recording filter

The new setting `showAdultInRecent` (UserDefaults `library.showAdultInRecent`, default
false) is applied in `filteredChannels` for `recentChannelsID` only. `noteRecent` still
records every channel.

The user asked for a visibility setting ("visible in recently viewed"). A display filter can
be switched back without losing anything.

Rejected: **not recording adult channels while the setting is off.** Turning it on later
would show nothing for the time before, and turning it off would have to delete entries.
The user's wording asks for visibility, not for a privacy mode.

### 2. One definition of "adult channel"

`AppModel.isAdult(_ channel: LiveChannel)` is true when the provider flags the channel
(`isAdult`), or its category is detected as adult by `isAdultCategory`. This is exactly what
the existing `showAdult` filter drops. `filteredChannels` uses the helper for both filters,
so the two cannot drift apart.

### 3. The toggle depends on "Erwachsenen-Kategorien anzeigen"

In `YouthProtectionSettings`, the new toggle sits below the existing one and is
`.disabled(!app.showAdult)`. A footer line explains that adult channels only appear there
when both are on. The stored value stays as it is while disabled.

Rejected: **turning the new setting off when `showAdult` goes off.** That changes a choice
the user made, without saying so.

### 4. Removing from the history

`AppModel.removeRecent(_ channelId:)` filters the id out of `recentChannels` and saves it the
same way as `noteRecent` (not in test runs).

`ChannelMenu` shows "Aus „Zuletzt gesehen“ entfernen" when `recentChannels` contains the
channel, so it appears in every context of that channel (list, pane), not only inside the
pinned entry. It is placed after the favourites item.

If the removed channel was selected in the "Zuletzt gesehen" list, it disappears from the
list. The detail pane then shows "No Channel Selected", like after hiding a channel.

Rejected: **only offering the item inside "Zuletzt gesehen".** The menu does not know which
list it is in. The item is also useful from "Alle", and harmless there.

### 5. Test switches without touching defaults

Debug runs share UserDefaults with the installed Fernsy, so the tests must not write
`library.showAdult` or the new key. In `debugBootstrap`:
- `IPTV_TESTADULT=<id,…>` treats these channels as adult (the demo has none);
- `IPTV_RECENT=<id,…>` sets the history in memory;
- `IPTV_SHOWADULT=0|1` and `IPTV_ADULTRECENT=0|1` set both settings in memory. While a
  switch is set, its `didSet` does not write to UserDefaults (a debug-only flag, like
  `debugFavoritesInMemory`).

## Risks / Trade-offs

- **[Adult channels remain in the stored history]** → That is the decision above. The entry
  can still be removed with the new menu item, or by turning off adult categories.
- **[The menu item appears outside "Zuletzt gesehen"]** → Accepted. It only appears when the
  channel actually is in the history.
