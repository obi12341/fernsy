## MODIFIED Requirements

### Requirement: Transcode fallback
When an item cannot be played locally, Fernsy SHALL ask Jellyfin for a transcode and play that
instead: known cases are video codecs this Mac cannot decode, including Dolby Vision profile 5
on a Mac that cannot decode it as Dolby Vision; a direct play that fails while opening SHALL be
retried once as a transcode.

#### Scenario: Dolby Vision profile 5
- **WHEN** the user plays a Dolby Vision profile 5 film on a Mac that decodes Dolby Vision
- **THEN** it plays directly as Dolby Vision with correct colours and the server shows no
  transcode

#### Scenario: Dolby Vision profile 5 without Dolby Vision decoding
- **WHEN** this Mac cannot decode a Dolby Vision profile 5 film as Dolby Vision
- **THEN** Jellyfin transcodes it to SDR

#### Scenario: Direct play fails
- **WHEN** the original file cannot be opened by the player
- **THEN** Fernsy switches to a Jellyfin transcode without the user doing anything
