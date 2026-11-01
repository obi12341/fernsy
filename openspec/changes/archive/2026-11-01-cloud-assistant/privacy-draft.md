# Privacy page: draft for the assistant (cloud-assistant 4.1)

Not published yet. `website/datenschutz.html` and `website/en/privacy.html` go live on every
push to `main` (pages.yml), and the assistant stays hidden until Fernsy Cloud launches. These
sections go into the pages with that launch, after the user has reviewed them (legal text of
mobilistics GmbH).

Note for that review: the current pages say the app transmits no personal data to anyone. That
is already incomplete without the assistant: iCloud sync (favourites, settings, logins in the
user's own iCloud) and Fernsy Cloud (encrypted recordings on our server) are not described
either. The launch needs all three.

## Deutsch (unter „Die App Fernsy“, als eigener Abschnitt)

### Assistent (Teil von Fernsy Cloud)

Wenn du den Assistenten nutzt, schickt Fernsy deine Anfrage und den bisherigen Verlauf des
Gesprächs an unseren Server und von dort an OpenRouter (OpenRouter, Inc., USA), das sie an das
Sprachmodell Claude von Anthropic (Anthropic, PBC, USA) weitergibt. Damit der Assistent antworten
kann, enthält die Anfrage die Daten, die er dafür braucht: Sendernamen, Programmdaten, Titel aus
deiner Film-, Serien- und Jellyfin-Bibliothek, deine Favoriten und zuletzt gesehene Inhalte sowie
Uhrzeit, Zeitzone, Sprache und Gerätetyp.

Vor der ersten Anfrage fragt Fernsy auf jedem Gerät nach deiner Einwilligung (Art. 6 Abs. 1 lit. a
DSGVO); du kannst sie in den Einstellungen unter Fernsy Cloud jederzeit widerrufen. Unser Server
speichert den Inhalt deiner Anfragen und Antworten nicht und schreibt ihn nicht in Protokolle; er
speichert nur Konto-Kennung, Zeitpunkt und Anzahl der verarbeiteten Tokens, um das monatliche
Kontingent zu zählen, und löscht diese Einträge nach 40 Tagen. Für die Verarbeitung bei OpenRouter
und Anthropic gelten deren Datenschutzbestimmungen; die Übermittlung in die USA stützt sich auf
[Grundlage der Übermittlung, z. B. EU-US Data Privacy Framework oder Standardvertragsklauseln:
vor Veröffentlichung prüfen].

## English (under "The Fernsy app", as its own section)

### Assistant (part of Fernsy Cloud)

When you use the assistant, Fernsy sends your request and the conversation so far to our server
and from there to OpenRouter (OpenRouter, Inc., USA), which passes it to the language model Claude
by Anthropic (Anthropic, PBC, USA). So that the assistant can answer, a request contains the data
it needs: channel names, program data, titles from your film, series and Jellyfin library, your
favorites and recently watched items, and the time, time zone, language and device type.

Before the first request on each device, Fernsy asks for your consent (Art. 6(1)(a) GDPR); you
can withdraw it at any time in Settings under Fernsy Cloud. Our server does not store the content
of your requests and answers and does not write it to logs; it stores only the account id, the
time and the number of tokens processed, to count the monthly allowance, and deletes these
entries after 40 days. OpenRouter's and Anthropic's privacy policies apply to their processing;
transfers to the USA are based on [basis of transfer, e.g. EU-US Data Privacy Framework or
standard contractual clauses: check before publishing].
