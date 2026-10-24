# channel-names Specification

## Purpose
How Fernsy shows the IPTV provider's channel and category names: without decoration, with country and quality tags that keep duplicates apart, and with the delivered name available in the channel info.

## Requirements

### Requirement: Cleaned channel and category names
Fernsy SHALL show IPTV channel and category names without provider decoration: a
recognised country prefix becomes a country tag, trailing quality markers become a quality
tag, and runs of decoration characters at the start or end are removed. Names in which
nothing is recognised, or which would become empty, stay exactly as delivered.

#### Scenario: Country prefix and quality
- **WHEN** a channel is named "|DE| RTL FHD"
- **THEN** it is shown as "RTL" with the tags "DE" and "FHD"

#### Scenario: Decoration only around a word
- **WHEN** a category is named "########## ADULT ##########"
- **THEN** it is shown as "ADULT"

#### Scenario: Nothing recognised
- **WHEN** a channel is named "Kanal Süd"
- **THEN** it is shown as "Kanal Süd" without tags

#### Scenario: Prefix forms
- **WHEN** channels are named "DE: ZDF", "|DE| ZDF", "[DE] ZDF", "DE - ZDF" and "DE ▎ ZDF"
- **THEN** each is shown as "ZDF" with the tag "DE"

#### Scenario: Not a country code
- **WHEN** a channel is named "TV: Classics"
- **THEN** it is shown unchanged, because "TV" is no country code

### Requirement: Tags stay visible
The country and quality tags SHALL be shown next to the cleaned name wherever a channel
appears in a list (channel list, guide, search, favourites), so duplicates such as "RTL"
with "DE"/"HD" and "RTL" with "AT"/"SD" stay distinguishable.

#### Scenario: Two feeds of one channel
- **WHEN** a category contains "DE: ZDF HD" and "DE: ZDF SD"
- **THEN** both rows read "ZDF" with the tags "DE HD" and "DE SD"

### Requirement: Channel info
The channel's context menu SHALL offer "Senderinfo …" (⌘I) showing the name as delivered
by the provider, the channel number, the category as delivered, the EPG id and whether
an archive is available.

#### Scenario: Looking up the raw name
- **WHEN** the user chooses "Senderinfo …" on "ZDF" with the tags "DE" and "HD"
- **THEN** the info shows the delivered name "DE: ZDF HD"
