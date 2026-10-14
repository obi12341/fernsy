# Fernsy – App Store Connect

Texte zum Einfügen in App Store Connect. Zeichenlimits stehen in Klammern; die aktuellen
Längen prüft `python3 scripts/check-store-texts.py`.

## Allgemein (sprachunabhängig)

| Feld | Wert |
|---|---|
| Bundle-ID | de.mobilistics.fernsy |
| Primäre Kategorie | Unterhaltung / Entertainment |
| Sekundäre Kategorie | Foto und Video / Photo & Video |
| Copyright | 2026 mobilistics GmbH |
| Preis | (festlegen) |
| Support-URL | (Pflicht – z. B. https://mobilistics.de/fernsy/support) |
| Marketing-URL | (optional) |
| Datenschutz-URL | (Pflicht – Text siehe unten, z. B. https://mobilistics.de/fernsy/datenschutz) |
| App-Datenschutz | „Keine Daten erfasst“ / “Data Not Collected” |
| Altersfreigabe | Empfehlung 18+: Fernsy zeigt ungefiltert, was der Anbieter liefert; Erwachsenen-Kategorien sind nur ausgeblendet, nicht gesperrt. |
| Verschlüsselung | Keine eigene (ITSAppUsesNonExemptEncryption = NO ist im Build gesetzt) |

---

## Deutsch

### Name (30)
Fernsy – IPTV Player

### Untertitel (30)
Live-TV, Filme & TV-Programm

### Werbetext (170)
Dein IPTV-Zugang als echte Mac-App: Live-TV mit Programmraster, Filme und Serien – schnell, nativ und ohne Werbung.

### Beschreibung (4000)
Fernsy ist ein schneller, nativer IPTV-Player für den Mac. Melde dich mit den Xtream-Codes-Zugangsdaten deines Anbieters an und schau Live-TV, Filme und Serien in einer aufgeräumten Mac-App – ohne Werbung und ohne Umwege über den Browser.

LIVE-TV
• Senderliste mit Kategorien, Suche und Favoriten
• Programmraster für alle Sender, mit Jetzt-Linie und Sendungsdetails
• Laufende und nächste Sendung direkt in der Senderliste und im Player
• Umschalten mit den Pfeiltasten, wie am Fernseher

FILME UND SERIEN
• Übersichtliche Poster-Ansicht, sortierbar nach Neuheit, Name oder Bewertung
• Details mit Handlung, Besetzung, Regie und Bewertung
• Serien mit Staffeln und Episoden
• Weiterschauen, wo du aufgehört hast

WIEDERGABE
• Hardware-Dekodierung über VideoToolbox, bis 4K
• Deinterlacing auf der Grafikkarte für ein ruhiges, scharfes Fernsehbild
• Nahtlose Wiederverbindung bei Netzaussetzern – ohne Neustart und ohne Wiederholungen
• Mehrere Tonspuren und Untertitel
• Vollbild, Tastaturkürzel und technische Infos mit Puffer-Diagramm

DATENSCHUTZ
Fernsy erfasst keine Daten. Deine Zugangsdaten liegen im Schlüsselbund deines Macs, und Fernsy verbindet sich ausschließlich mit deinem Anbieter.

WICHTIG
Fernsy enthält keine Sender, Filme oder sonstigen Inhalte und verkauft keine Abonnements. Du benötigst einen Zugang (Xtream Codes API) bei einem IPTV-Anbieter deiner Wahl. Bitte nutze Fernsy nur mit Inhalten, für die du die Rechte besitzt.

### Schlüsselwörter (100)
Xtream,Xtream Codes,EPG,TV Programm,Fernsehen,Live TV,Streaming,Sender,Serien,Filme,VOD

### Neuerungen in dieser Version (4000)
Die erste Version von Fernsy.

---

## English (U.S.)

### Name (30)
Fernsy – IPTV Player

### Subtitle (30)
Live TV, movies & TV guide

### Promotional Text (170)
Your IPTV subscription as a real Mac app: live TV with a full program guide, movies and series – fast, native and ad-free.

### Description (4000)
Fernsy is a fast, native IPTV player for the Mac. Sign in with the Xtream Codes credentials from your provider and watch live TV, movies and series in a clean Mac app – no ads, no detours through a web browser.

LIVE TV
• Channel list with categories, search and favorites
• Program guide grid for every channel, with a now line and show details
• What’s on now and next, right in the channel list and the player
• Switch channels with the arrow keys, just like on a TV

MOVIES AND SERIES
• Clean poster view, sorted by newest, name or rating
• Details with plot, cast, director and rating
• Series with seasons and episodes
• Pick up right where you left off

PLAYBACK
• Hardware decoding with VideoToolbox, up to 4K
• GPU deinterlacing for a steady, sharp TV picture
• Seamless reconnects when the network drops out – no restart, no repeated scenes
• Multiple audio tracks and subtitles
• Full screen, keyboard shortcuts and technical info with a buffer chart

PRIVACY
Fernsy collects no data. Your credentials stay in your Mac’s keychain, and Fernsy only connects to your provider.

PLEASE NOTE
Fernsy does not include any channels, movies or other content, and does not sell subscriptions. You need an account (Xtream Codes API) with an IPTV provider of your choice. Please only use Fernsy with content you have the rights to watch.

### Keywords (100)
Xtream,Xtream Codes,EPG,TV guide,television,live TV,streaming,channels,series,movies,VOD

### What’s New in This Version (4000)
The first release of Fernsy.

---

## App Review – Hinweise für die Prüfung (englisch einreichen)

### Sign-in information
Server / username / password of a working test account. (Fill in before submitting – App Review rejects apps it cannot sign in to.)

### Notes
Fernsy is a player for the user’s own IPTV subscription (Xtream Codes API). It does not include, sell, link to or recommend any channels or content, and it has no in-app purchases. All content shown comes from the server the user signs in to; the provided test account is supplied by us for review only.

Network: Most Xtream Codes servers only offer plain HTTP and redirect streams to changing hosts, so the app uses an App Transport Security exception (NSAllowsArbitraryLoads). Credentials are stored in the keychain; the app collects no data.

The screenshots use fictional demo content (channels, programs, posters) rendered by us; the video still is “Big Buck Bunny” (© Blender Foundation, CC BY 3.0).

---

## Datenschutzerklärung (Entwurf für die Datenschutz-URL)

> Entwurf – bitte vor der Veröffentlichung rechtlich prüfen und mit Anschrift/Kontakt ergänzen.

### Deutsch

**Datenschutzerklärung für Fernsy**

Verantwortlich: mobilistics GmbH, [Anschrift], [E-Mail]

Fernsy erhebt, speichert und überträgt keine personenbezogenen Daten an uns oder an Dritte. Es gibt keine Analyse-, Tracking- oder Werbedienste.

Die von dir eingegebenen Zugangsdaten (Server-Adresse, Benutzername, Passwort) werden ausschließlich lokal im Schlüsselbund deines Macs gespeichert. Fernsy verbindet sich nur mit dem Server deines IPTV-Anbieters, um Senderlisten, Programmdaten und Streams abzurufen. Für die dabei verarbeiteten Daten ist dein Anbieter verantwortlich; es gilt dessen Datenschutzerklärung.

Favoriten, Wiedergabepositionen, Einstellungen sowie zwischengespeicherte Katalog- und Programmdaten liegen nur lokal auf deinem Mac und werden beim Löschen der App entfernt.

Bei Fragen erreichst du uns unter [E-Mail].

### English

**Privacy Policy for Fernsy**

Controller: mobilistics GmbH, [address], [email]

Fernsy does not collect, store or transmit any personal data to us or to third parties. There are no analytics, tracking or advertising services.

The credentials you enter (server address, username, password) are stored only locally in your Mac’s keychain. Fernsy connects only to your IPTV provider’s server to load channel lists, program data and streams. Your provider is responsible for the data processed there; its privacy policy applies.

Favorites, playback positions, settings and cached catalog and program data are stored only locally on your Mac and are removed when you delete the app.

If you have any questions, contact us at [email].
