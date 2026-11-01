# Tasks

## 1. The row

- [x] 1.1 Apple TV: "Next Up" row in `JellyfinOverviewPage` right after Continue Watching, from `store.nextUp` (WideCard: series name, `VODItem.jellyfin(item).subtitle`, thumb; no progress), selecting plays; identifiers `jellyfin.next.<id>`
- [x] 1.2 iOS: the same row in the Übersicht of `JellyfinSearchViews.swift`
- [x] 1.3 Mac: a `PagingCarousel` "Next Up" after Continue Watching in `JellyfinOverviewView`, with `JellyfinWideCard`, the item menu and "Open Series"

## 2. Verification

- [x] 2.1 Apple TV UI test with the local test Jellyfin (`scripts/jellyfin-test-server.sh` on 127.0.0.1:8097; skips without it, like the other overview tests): after an episode is marked watched (or with a fixture series in progress), Übersicht shows `jellyfin.next.*` below Continue Watching and selecting one plays it. If the shared test server is not available on this machine, check the row on "Apple TV WZ" with the user instead and say so Confirmed by the user on "Apple TV WZ", 2026-11-01.
- [x] 2.2 iOS: the same check on "iPad Air 11-inch (M4)" (`scripts/ios-uitest.sh`), or on the user's iPad Confirmed by the user on the iPad, 2026-11-01.
- [x] 2.3 Mac: a dev run (`scripts/dev-run.sh` with `JF_SERVER`/`JF_USER`/`JF_PASS` of the test server and `JF_KEYCHAIN_SUFFIX=test`), or the user's Mac app, shows the row Checked by the user on their Mac (release build), 2026-11-01.
- [x] 2.4 `scripts/test.sh` and `openspec validate --all --strict` pass

## Workflow follow-up

- Archive on `change/jellyfin-overview-next-up`, merge into `main` and push with the user's
  consent. Release notes: DE "Die Jellyfin-Übersicht zeigt jetzt auch „Nächste Folge“ – die
  nächsten Episoden deiner Serien direkt unter „Weiterschauen“." / EN "Jellyfin's overview now
  also shows "Next Up" – your series' next episodes right below "Continue Watching"."
