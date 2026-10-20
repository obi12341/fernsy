# Design

## Context

Fernsy is built around one Xtream account: `AppModel` holds `credentials`, catalog arrays
and per-account caches (`Application Support/Fernsy/<accountKey>/`); `CredentialStore`
keeps one keychain item (account "xtream"); `FernsyApp` shows `LoginView` while
`credentials == nil`; `LibraryView` has one sidebar section list (`LibrarySection`) and a
`CategoryColumn`; `MovieGridView`/`SeriesGridView`/detail views use the Xtream models
(`Movie`, `Series`, `Episode`) directly; posters go through `RemoteImage`/`ImagePipeline`.
The playback analysis (archived change `analyze-jellyfin-playback`) documents auth, item
and stream endpoints of the user's Jellyfin 12.2.0 server. See proposal.md for motivation.

## Goals / Non-Goals

**Goals:** Jellyfin next to IPTV without disturbing the IPTV paths; a browser that is fast
with ~2000 items; server-side watched state and favorites; ready for the playback run.

**Non-Goals:** playback, music, several servers, sharing one model with Xtream.

## Decisions

### Separate Jellyfin module, owned by AppModel
New `Fernsy/Jellyfin/`: `JellyfinClient` (async URLSession, Codable), `JellyfinModels`
(`JFItem`, `JFUserData`, `JFLibrary`, `JFSession`), `JellyfinStore` (`@MainActor
ObservableObject`: session, libraries, films, series, home rows, caches, user-data
writes). `AppModel` owns it as `app.jellyfin` and injects it as an environment object.
- Rejected: a common media model for Xtream and Jellyfin now – Xtream items are flat and
  integer-keyed, Jellyfin items are typed and string-keyed with user data; unifying them
  would touch every IPTV view for no user benefit. The playback run maps both to `PlayItem`.
- Rejected: an account abstraction for arbitrary accounts – the user chose one IPTV plus
  one Jellyfin account; a list of accounts can come later.

### Session and authentication
`Authorization: MediaBrowser Client="Fernsy", Device="<Mac name>", DeviceId="<id>",
Version="<app version>", Token="<token>"` on every request; the device id is a UUID created
once and kept in UserDefaults. Sign-in: `GET /System/Info/Public` (must have `ProductName`
"Jellyfin Server" and an `Id`), then `POST /Users/AuthenticateByName`. Keychain item
account "jellyfin" holds `{server, serverId, serverName, version, userId, userName, token}`;
the password is never stored. HTTP 401 on any request marks the session expired (sidebar
notice + "Sign in again"); Sign Out calls `POST /Sessions/Logout`, then deletes the item.

### Library data
- Libraries: `GET /UserViews` filtered to `CollectionType` `movies` and `tvshows`.
- Items: `GET /Items?ParentId=<lib>&IncludeItemTypes=Movie|Series&Recursive=true` paged
  (500 per page) with fields for the grid only (`Genres, DateCreated, PremiereDate,
  ProductionYear, CommunityRating, OfficialRating, ImageTags, UserData,
  RecursiveItemCount`); detail fields (`Overview, People, MediaStreams, MediaSources,
  Studios, RunTimeTicks`) are fetched per item when a detail view opens.
- Series: `GET /Shows/{id}/Seasons` and `/Shows/{id}/Episodes?seasonId=` with UserData.
- Home: resume items, `GET /Shows/NextUp`, `GET /Items/Latest` per library.
- Endpoint spelling of user-specific routes changed across Jellyfin versions (`/Users/{id}/…`
  vs `/UserItems/…`, `/UserPlayedItems/{id}`, `/UserFavoriteItems/{id}`); the client uses
  the forms the user's 12.2.0 server answers and keeps them in one place (verified first
  in task 1.2).
- Writes: played/unplayed and favorite/unfavorite per item; the UI updates optimistically
  and reverts with a message when the request fails; series/season counts are refreshed
  from the server afterwards.

### Cache
Films and series lists (with user data) are cached as JSON in
`Application Support/Fernsy/jellyfin-<serverId>-<userId>/` and shown first at launch, then
refreshed in the background (same stale-while-revalidate idea as the IPTV catalog). User
data is refreshed whenever a Jellyfin section becomes visible (cheap `Fields=UserData`
request), so marks from other clients show up.

### Artwork
`/Items/{id}/Images/{Primary|Backdrop|Thumb}?tag=<imageTag>&maxHeight=<px>&quality=90`
through the existing `RemoteImage`/`ImagePipeline` (the tag makes URLs change when artwork
changes, so the existing URL-keyed cache stays correct). Episode thumbnails fall back to the
series backdrop.

### UI integration
- `LibrarySection` gains `jellyfinHome`, `jellyfinFilms`, `jellyfinSeries`; the sidebar
  shows an "IPTV" group (existing sections) only with Xtream credentials and a "Jellyfin"
  group only with a Jellyfin session. Existing IPTV sections and their behaviour are unchanged.
- `CategoryColumn` gets the Jellyfin rows (All, Favorites, libraries, genres).
- New views `JellyfinHomeView`, `JellyfinGridView` (films/series), `JellyfinFilmDetailView`,
  `JellyfinSeriesDetailView`, reusing `PosterCard`, `RemoteImage`, the sort menu style and
  the detail layout of the IPTV views where possible. Navigation via the existing
  `NavigationStack` path with new destination types.
- `FernsyApp` shows `LibraryView` when any account exists. `LoginView` gets an IPTV/Jellyfin
  picker; `SettingsView` gets a Jellyfin section (server, version, user, Sign Out / Add
  Jellyfin Server as a sheet with the same form).
- Play buttons exist but are disabled (help: "Playback follows in a later version").

### Network permissions
Jellyfin servers are often on the local network. The App Sandbox already has
`network.client` and ATS allows HTTP; macOS asks for local-network permission, which needs
`NSLocalNetworkUsageDescription` in Info.plist (German/English via InfoPlist strings).
Verified in the Release (sandboxed) build, not only Debug.

### Writes only on fetched films, series, seasons and episodes
Jellyfin applies played/favorite writes on a folder to every item below it, and an unknown
id (e.g. all zeros) can resolve to the user's root folder. `JellyfinStore` therefore only
marks items of type Movie, Episode, Season or Series that came from the server.
- Incident during implementation (2026-10-20): a failure-path test with an all-zero id marked
  the user's whole library as played. It was restored from Fernsy's library cache (films and
  series counts exactly) and the incident timestamp (never-played episodes exactly); 20 partly
  watched episodes were restored by estimate and lost their resume positions. Failure paths
  are now tested offline (unreachable server), and write tests back up the affected user
  data first.

### Sorting without parsing dates
Grids sort by Jellyfin's ISO 8601 strings (`addedKey`, `releaseKey`), which are UTC in one
format and therefore sort chronologically.
- Pitfall found after the first build: parsing the dates inside the sort comparator (a new
  `ISO8601DateFormatter` plus a regex per comparison) ran on every body evaluation and kept
  the main thread ~97 % busy while scrolling; with string keys it is ~88 % idle. Profiling:
  `JF_CACHEONLY=<server>|<serverId>|<userId>` shows the cached library without signing in.

## Risks / Trade-offs

- [Large libraries] → paged loading, grid fields only, cache; ~2000 items tested on the
  user's server.
- [API differences between Jellyfin versions] → endpoints in one place; only 12.2.0 tested;
  minimum supported version stated in the README.
- [Tests write to the user's server (watched/favorite)] → only on one test item each, state
  restored afterwards; everything else read-only.
- [App Review needs a Jellyfin account later] → out of scope here; noted for the playback
  change (demo server could expose a minimal Jellyfin-compatible API).

## Open Questions

- Should IPTV and Jellyfin films/series ever be shown in one combined list? Not now; the
  groups stay separate.
