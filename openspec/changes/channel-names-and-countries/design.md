# Design

## Context

`LiveChannel.name` and `XCategory.name` are shown as delivered everywhere: the channel
list, guide, player title, zap banner, search, menu bar, recordings and file names. The
search key (`makeSearchKey(name)`) is built from the raw name.

- **Favourites:** global, stored in `UserDefaults` "library.favorites" as "live:<id>" keys,
  with their own sidebar section.
- **Live TV categories:** the category column offers "Alle" plus the provider's categories
  (flat), with a filter field.
- **Zapping:** follows the playing channel's own category.

The design source is the Claude Design project "Fernsy Redesign", "Sendernamen bereinigen".
The country groups with sub-levels in that source are deliberately not adopted, because
providers deliver flat categories.

## Goals / Non-Goals

**Goals:**
- Readable names with tags, parsed once per item.
- Raw names stay reachable (Senderinfo) and searchable.
- Live TV gets "Favoriten" and "Zuletzt gesehen" next to "Alle".

**Non-Goals:**
- Grouping categories.
- Renaming by the user.
- Row styling beyond name and tags; the rest is `redesign-live-tv`.

## Decisions

### 1. Parser: `ChannelName.parse(_:) -> ChannelName`

`ChannelName` is a pure value type in `Fernsy/Xtream/ChannelName.swift` with the fields
`raw`, `name`, `country?` and `quality?`. The steps, in this order:

1. **Trim decoration:** remove leading and trailing runs of `# = * ★ ▎ | ~ - _ • ·` and
   spaces.
2. **Country prefix:** one of `|CC|`, `[CC]`, `(CC)`, `CC:`, `CC -`/`CC –`, `CC |`,
   `CC ▎`, or `CC` followed by one of those separators. Here `CC` is 2–4 capital letters
   that are a known code: ISO 3166 alpha-2 from `Locale.Region.isoRegions` plus the
   IPTV-usual `UK`, `EN`, `EXYU`, `ARAB`, `LAT`, `USA`, `GER`.

   This list keeps words like "TV", "HD" or "NEWS" from turning into tags. Without a
   separator (for example "DE ZDF") nothing is recognised, because too many real names
   start with two capital letters ("RT Doc").
3. **Quality suffix:** trailing tokens matching `SD|HD|FHD|UHD|4K|8K` with an optional
   `raw`, or `HEVC|H265|H\.265|50FPS|60FPS`. The first such token becomes the tag ("HDraw"
   → "HD raw", "FHD HEVC" → "FHD"); all trailing matches are removed. Superscripts such as
   ᴴᴰ are mapped to HD.
4. **Trim again:** if the result is empty, the whole parse falls back to the raw name
   without tags.

The parse runs once in `LiveChannel.init(from:)` and `XCategory.init(from:)` and is stored.
The catalog cache decodes through the same initialisers, so cached catalogs are parsed too.
A debug self-test, `IPTV_NAMETEST=1`, runs the spec's examples and a set of edge cases
("RT Doc", "TV: Classics", "ARD-alpha", "#### ADULT ####", "UK: BBC One FHD",
"ZDF HDraw Cable").

Rejected: parsing in the views. That repeats the work for thousands of rows on every
redraw and spreads the rules.

Rejected: mapping codes to country names ("Deutschland"). The tags only distinguish
duplicates, and the design shows the code.

### 2. Where the cleaned name is used

`LiveChannel.displayName` and `XCategory.displayName` are used in:
- `ChannelRow` (list, search, favourites), with a `NameTag` view for the tags
- the guide's channel column, also with tags
- the category column, with the country tag
- the player title and zap banner (`PlayItem.title`)
- the menu bar and the Recordings list (`Recording.channelName` is stored cleaned at
  scheduling)
- the recording file name, as "Name (CC)"

The raw name stays in the search key, so searching "DE: ZDF" or "ZDF" both match.
Recordings scheduled before this change keep their stored names.

`NameTag` is a small outlined label, 9.5 pt bold, using `Theme.tagBorder` from the
foundation. It goes into `Fernsy/Views/Design/`.

### 3. Pinned Live TV entries

The category column gets two pseudo categories after "Alle": `__favorites` (the favourite
channels) and `__recent` (recently played). `AppModel.filteredChannels(categoryID:)`
resolves both. The guide uses the same function, so both views follow.

`AppModel.recentChannels` holds up to 20 ids, newest first. It is updated in `play(_:)`
for live channels and stored in `UserDefaults` "live.recent". It is global like the
favourites; the ids are per provider, but both stores already behave that way. Zapping is
unchanged: it follows the channel's own category.

The Favourites sidebar section stays. The pinned entry is a shortcut inside Live TV.

### 4. Senderinfo

The `ChannelRow` context menu and the Live TV selection get "Senderinfo …" (⌘I). It opens a
sheet listing the delivered name, the number (stream id), the delivered category name, the
EPG id and whether an archive is available, with a Copy button for the raw name.

## Risks / Trade-offs

- **False positives in the prefix rule.** The code list and the separator requirement keep
  them rare, and the raw name stays visible in Senderinfo. Edge cases go into the self-test
  when the user reports them.
- **Renamed recordings.** New recordings get file names with "(CC)", old ones keep theirs.
  Both play and are listed the same way.
