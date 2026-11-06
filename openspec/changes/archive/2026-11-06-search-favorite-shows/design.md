# Design

## Context

- **Mac search today** (`Fernsy/Views/SearchResultsView.swift`): `SearchModel` builds a
  `SearchIndex` over channels, films, series, recordings and Jellyfin titles in the background
  and runs each query 150 ms after the last keystroke, off the main thread. It rebuilds when
  `AppModel`, `JellyfinStore` or `Recorder` change. Results are grouped in `SearchResultsView`.
- **Guide data** (`EPGStore`, FernsyCore): loaded per channel (`get_short_epg`/XMLTV cache),
  one `ChannelGuide` per channel with published `entries`. `load(_ ids:client:timeout:)` loads
  several channels and waits at most `timeout` (made for the MCP tools). `search(_:on:from:to:)`
  matches title or description over loaded guides.
- **Existing show searches:** Apple TV and iPhone/iPad (`TVModel.liveSearchHits`) search titles
  of favourites, recently watched and the first visible channels (50), now or later, running
  first, at most 12. The MCP tool `search_program` searches favourites and recently watched,
  title and description.
- **Recording from the guide:** `Recorder.schedule(entry, on:)` with padding and the stream
  limit, `.present()` shows a refusal or notice; `recording(channelId:entry:)` finds a plan.

## Goals / Non-Goals

**Goals:**
- Shows of the favourite channels in the toolbar search, without making typing slower.
- The same play/record behaviour as the guide.

**Non-Goals:**
- Other channels, past shows (catch-up), description matching (see proposal).
- Changing the Apple TV/iOS search or the MCP tool.

## Decisions

### 1. Favourites only, at most 50
The channels are `filteredChannels(categoryID: favoriteChannelsID)`, i.e. visible favourites
in the user's order, capped at 50 like the other show searches.

Rejected:
- **All channels:** the guide is loaded per channel; a provider with 500+ channels would get
  hundreds of requests per search.
- **Favourites plus recently watched (as Apple TV, MCP):** the user asked for favourites;
  recently watched channels add hits from channels the user only zapped through.

### 2. Titles only, now or later
Matching uses `makeSearchKey` on the title, like the other groups and Apple TV; shows with
`end > now`. Running shows first, then by start.

Rejected:
- **Descriptions too (as `EPGStore.search`, MCP):** a query like "krimi" or a name would list
  dozens of shows that only mention it.

### 3. Show search beside the index, not in it
Guide entries change every few minutes and arrive per channel; putting them into the
`SearchIndex` would rebuild it constantly. `SearchModel` keeps the favourites list and, per
query, scans their loaded entries (50 channels × ~100 entries is a few thousand title keys)
in the same detached task as the index search. Title keys are computed once per guide load
and cached by channel and entry.

### 4. Loading the favourites' guides when a search starts
On the first non-empty query of a search session, `SearchModel` starts one background
`EPGStore.load(favouriteIds, timeout: 20)` for all favourites (it skips fresh full guides and reads its disk cache first; the channel list alone has only the quick now/next answer), and runs the
current query again when it returns. It does not run again for every keystroke; a new search
session (field cleared and typed again) loads again only what is still missing. Typing never
waits; the other groups show at once.

Rejected:
- **Observing every `ChannelGuide`:** 50 publishers re-running the query on each arrival;
  one re-run after the batch is enough and simpler.
- **Loading all favourites' guides at launch:** extra requests for users who never search.

### 5. Show rows and actions
A new group "Shows" (German "Sendungen") after channels, with rows: channel logo, title,
"Heute 20:15–21:45 · Das Erste", a "läuft" badge for running shows and the record dot for
planned ones. Click: running → `app.play(channel)`; later → a confirmation dialog
"Aufnehmen?" that calls `recorder.schedule(entry, on: channel).present()`, or, when planned,
"Aufnahme geplant" with the option to remove it. Context menu: play channel, record/remove
recording, show in guide (switches Live TV to the guide view on that channel). Limit 20 rows
with "show all", like channels.

## Risks / Trade-offs

- **First search after launch:** the shows group may appear a few seconds after the others while
  guides load. Accepted; the spec allows it.
- **Providers with slow guide endpoints:** at most 20 s; channels that did not load are left out.
- **Stale hits:** a show that ends while the results are open stays listed until the next
  keystroke. Accepted.
