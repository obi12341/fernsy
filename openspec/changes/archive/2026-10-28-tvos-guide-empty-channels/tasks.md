# Tasks

## 1. Guide rows

- [x] 1.1 FernsyCore `GuideGaps.free(shows:window:minimum:)` (design 1); `GuideRow`: the free stretches as `GuideGapCell` buttons with hatched fill and the texts; click plays the channel (design 3); paging from gaps (design 4); identifiers (design 6).
- [x] 1.2 `IPTV_TESTNOEPG=<channel id>` on Apple TV (design 5).
- [x] 1.3 Strings: "No program data" with its German translation (from the Mac catalog); `LocalizationTests` green.

## 2. Verification

- [x] 2.1 UI test, demo server with `IPTV_TESTNOEPG=102`: in the guide, Down from channel 101's running show lands on 102's bar, clicking it plays channel 102 (`player.state` playing); screenshot of the row.
- [x] 2.2 Unit tests (`scripts/test.sh`) for `GuideGaps.free`: no listings, listings ending early, a gap between shows, gaps under 15 minutes left out; `GuideUITests` green.
- [x] 2.3 Full Apple TV UI suite and `scripts/test.sh` green.
- [ ] 2.4 Real Apple TV, Release build: the user checks the guide with their provider's channels without listings.
