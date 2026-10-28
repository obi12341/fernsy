# Proposal

## Why

Start on Apple TV shows a large "Continue Watching" entry, the row "Continue Watching" and
"Recently Added". Without anything started, which is how every new installation begins, it is
one row of posters on an empty screen. Start is the first screen after launch and should show
what the account offers: live TV, tonight's programme, the library by category, recordings.

## What Changes

- Without anything to continue, the large entry becomes a spotlight on the newest film (Jellyfin
  or the provider) with its backdrop, "Play" and "Info".
- New rows, each shown only when it has entries:
  - "Jetzt live": the favourite channels (else the recently watched, else the first channels)
    with the show on now, its progress and time left; a click plays the channel.
  - "Nächste Folge": Jellyfin's next episodes.
  - "Heute Abend": shows starting tonight at prime time (20:00–21:30) on those channels; a click
    plays a running show's channel or offers to record a later one.
  - Rows of the provider's largest film and series categories, and of the most common Jellyfin
    genres.
  - "Deine Aufnahmen": the newest finished recordings.
  - "Bestbewertet": the provider's best rated films.
- Order: large entry, Jetzt live, Weiterschauen, Nächste Folge, Heute Abend, Zuletzt hinzugefügt,
  category and genre rows, Deine Aufnahmen, Bestbewertet.

Out of scope:
- Settings to choose or reorder rows (to be decided after trying it).
- The Mac app's home page.
- Top Shelf.

## Capabilities

### New Capabilities

### Modified Capabilities
- `apple-tv`: Start's content.

## Impact

- `FernsyTV/Screens/StartScreen.swift`, new row views; `FernsyTV/Model/TVModel+Library.swift`
  (rows computed once per catalog change, not per redraw: large catalogs have 30,000 films).
- UI tests for Start; German strings.
