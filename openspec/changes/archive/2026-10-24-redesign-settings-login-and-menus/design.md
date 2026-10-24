# Design

## Context

**Sign-in:** `LoginView` shows a TV symbol, a segmented IPTV/Jellyfin picker and the form
(`IPTVSignInForm` / `JellyfinSignInForm`). Errors appear in red below the whole form.
`XtreamError` distinguishes `invalidServer`, `authFailed` and `http`; network errors are
`URLError`.

**Settings:** `SettingsView` is one long grouped form with sections IPTV, Jellyfin,
Inhalte (adult toggle), Sprache & Untertitel, and Zeitversetzt & Aufnahmen (with the menu
bar toggle). Adult categories are detected by name markers (`AppModel.isAdultCategory`).

**Menu bar:** The item shows `tv`, or `record.circle.fill` while recording; both are
template images. The menu has running recordings, the next one, open, show recordings and
quit.

**Log window:** It already has levels with colour, symbol and text, a toolbar with run,
level, area and search, Copy/Save/Clear, and monospaced millisecond times. Nothing changes
there.

**Design source:** Claude Design "Fernsy Redesign", `Anmeldung.dc.html`,
`Einstellungen.dc.html` and `Menueleiste.dc.html`.

## Goals / Non-Goals

**Goals:**
- A clear first decision at sign-in.
- Errors where they belong.
- Settings in tabs.
- Transparent youth protection.
- A recording dot and a quit warning in the menu bar.

**Non-Goals:**
- Account semantics, settings semantics, the log.

## Decisions

### 1. Sign-in cards and field errors

`LoginView` shows the app icon, "Willkommen bei Fernsy" and two selectable cards:
- **IPTV:** "IPTV-Anbieter (Xtream Codes)" with "Live-TV, Programm, Filme und Serien deines
  Anbieters".
- **Jellyfin:** "Jellyfin-Server" with "Filme und Serien von deinem eigenen Server".

The selected card gets an accent border. The form follows below. The footer always shows
"Fernsy sammelt keine Daten. Zugangsdaten bleiben im Schlüsselbund dieses Macs."

The forms classify their error:
- `XtreamError.invalidServer`, a `URLError` (host not found, cannot connect, timeout) or
  `JellyfinError.invalidURL` concerns the server field.
- `authFailed` or HTTP 401/403 concerns username and password.
- Anything else stays below the form.

The concerned fields get a red rounded outline, and the message sits directly below them.

Rejected: keeping the segmented control. The design makes the account type the first,
explained decision.

### 2. Settings with tabs

`SettingsView` becomes a `TabView` with toolbar tabs:
- **Konten** (person.crop.circle): IPTV and Jellyfin, as today.
- **Wiedergabe** (play.rectangle): language & subtitles, and the timeshift length.
- **Aufnahmen** (record.circle): padding, storage location, and the menu bar item, which
  moves here.
- **Jugendschutz** (hand.raised): the adult toggle, plus a list of detected categories
  ("Live TV · <name as delivered>", likewise for Filme and Serien) with their count.

The window width is fixed at 560, and its height follows the tab's content.

### 3. Menu bar dot and quit warning

`MenuBarLabel` draws its own `NSImage` with a drawing handler. The `tv` symbol is drawn
tinted with the menu bar's label colour, so it resolves for light and dark menu bars at
draw time. While recording, a red dot of 6 pt is added at the bottom right. The image is
not a template, so the red stays red.

While recording, the menu shows a disabled line "Fernsy beenden stoppt die laufende
Aufnahme" right above "Fernsy beenden".

Rejected: `record.circle.fill` alone, which is what the app shows today. Template rendering
makes it monochrome, and it replaces the app's symbol.

## Risks / Trade-offs

- **The tinted menu bar image could look off** if the menu bar uses unusual vibrancy.
  Checked by the user, since the menu bar cannot be screenshotted per window.
