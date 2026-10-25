## ADDED Requirements

### Requirement: Adult channels in Zuletzt gesehen
Settings › Youth protection SHALL offer "Erwachsenen-Sender unter „Zuletzt gesehen“
anzeigen", off by default. While it is off, adult channels (marked as adult by the provider
or in a category detected as adult) SHALL NOT appear in "Zuletzt gesehen", in the list, the
guide or the entry's count. The history keeps them, so turning the setting on shows them
again. The setting is disabled while adult categories are not shown, because adult channels
are hidden everywhere then.

#### Scenario: Default
- **WHEN** adult categories are shown and the user has watched an adult channel and then "Nordlicht 1"
- **THEN** "Zuletzt gesehen" lists "Nordlicht 1" but not the adult channel

#### Scenario: Setting turned on
- **WHEN** the user turns on "Erwachsenen-Sender unter „Zuletzt gesehen“ anzeigen"
- **THEN** the adult channel appears in "Zuletzt gesehen" again, in the order it was watched

#### Scenario: Adult categories hidden
- **WHEN** "Erwachsenen-Kategorien anzeigen" is off
- **THEN** the new setting is disabled and adult channels do not appear in "Zuletzt gesehen"
