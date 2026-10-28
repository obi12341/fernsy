# Design

## Context

`StartScreen` builds its rows from `TVModel.continueWatching` and `recentlyAdded` in `body`.
The model publishes often (recorder, Jellyfin, guide), so anything computed in `body` runs on
every redraw; with a catalog of 30,000 films (the user's provider) sorting and grouping there
would stall the screen (as the per-channel adult check froze Live TV).

## Goals / Non-Goals

**Goals:** a full Start for a new installation; no work per redraw on large catalogs.
**Non-Goals:** personalisation beyond what the app already knows (favourites, recent, resume).

## Decisions

### A. Rows computed once per catalog change

`StartRows` (spotlight, categories, genres, best rated) is built in a `.task(id:)` keyed by the
catalog's sizes and the Jellyfin lists' sizes, and kept in `@State`. Live and tonight rows read
the guide, which loads per channel: the task loads the guide of their channels (at most 12).

### B. Row choice

- Jetzt live: favourites first, else recently watched, else the first 12 visible channels, so the
  row is never empty for a new account.
- Heute Abend: shows starting 20:00–21:30 today, at most one per channel, sorted by start.
- Categories: the three film and two series categories with the most entries (adult categories
  are already filtered from the catalog), each row its newest 15; Jellyfin: the two most common
  film genres. Titles "Filme · <name>", "Serien · <name>", "Jellyfin · <genre>".
- Bestbewertet: films rated 7 or more with a poster, best first, 15.
- Spotlight without anything to continue: the first entry of Zuletzt hinzugefügt that is a film,
  with its backdrop (Jellyfin, or the provider's film info, loaded on demand).

Rejected: one big "for you" mixed row (hard to scan with a remote); horizontal category chips
on Start (Films and Series tabs already offer categories).

### C. As built

- The backdrop of the large entry stays behind the whole screen; with many rows it fades as
  Start scrolls (to 15 % after 600 pt), so the rows below read on the dark background.
- The same poster now shows in several rows at once; `ImagePipeline` joins loads of the same
  image in flight instead of downloading it once per row (the poster test caught this). Its log
  line names the size, since the large entry may use a poster as its backdrop at 1920 px.
- Checked with the user's catalog (11,000 channels, 31,000 films) without streams: Start and
  scrolling stay responsive; the category rows there are "DE • Drama / Liebesfilme" and the like.

## Risks / Trade-offs

- [Without favourites or history, Jetzt live takes the first channels] → with some providers
  those are placeholders ("Welcome Channel", event channels). Open for the user: keep, or skip
  channels without programme data, or hide the row until there are favourites.

- [Many rows make Start long] → rows only appear with entries; the order puts live and resume
  first. Settings for rows are left for after the user has tried it.
