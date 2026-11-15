# Spec Delta

## ADDED Requirements

### Requirement: Card menu in Weiterschauen and Nächste Folge on Apple TV
A long press on a card in "Weiterschauen" or "Nächste Folge", on Start and on Jellyfin's
Übersicht, SHALL open a menu: "Fortsetzen" for a started item or "Abspielen", "Von Anfang an" for
a started item, "Zur Serie" for an episode of an IPTV or Jellyfin series, and "Details" for a
film. A click SHALL keep playing the item from where the user stopped.

#### Scenario: Jellyfin episode in Weiterschauen
- **WHEN** the user long-presses a partly watched Jellyfin episode in Start's "Weiterschauen" and chooses "Zur Serie"
- **THEN** the series page opens with that episode as "Nächste Episode", and Back returns to Start

#### Scenario: Next episode on Übersicht
- **WHEN** the user long-presses an episode in "Nächste Folge" on Jellyfin's Übersicht
- **THEN** the menu offers "Abspielen" and "Zur Serie", without "Von Anfang an"

#### Scenario: Starting over
- **WHEN** the user long-presses a partly watched film in "Weiterschauen" and chooses "Von Anfang an"
- **THEN** the film plays from its start

#### Scenario: Click unchanged
- **WHEN** the user clicks a partly watched episode in "Weiterschauen"
- **THEN** it plays from where the user stopped

### Requirement: Back from an episode to its series on Apple TV
An episode started from "Weiterschauen" or "Nächste Folge" (Start or Übersicht) or from Start's
large entry SHALL have its series page beneath the player: when the player closes, the series
page SHALL show, and Back from it SHALL return to Start or Übersicht. Films, and episodes started
elsewhere, SHALL return to where they were started.

#### Scenario: Back after an episode
- **WHEN** the user plays S2 F4 of a series from "Weiterschauen" and presses Back until playback stops
- **THEN** the series page shows with Staffel 2, and Back again returns to Start

#### Scenario: Next episode played on
- **WHEN** the next-episode countdown starts S2 F5 and the user then stops playback
- **THEN** the same series page shows, offering S2 F6 or S2 F5 as the next episode

#### Scenario: Film unchanged
- **WHEN** the user plays a film from "Weiterschauen" and stops it
- **THEN** Start shows again

#### Scenario: Series page unchanged
- **WHEN** the user plays an episode from its series page and stops it
- **THEN** the series page shows once, not a second copy of it
