# Tasks

No app behaviour changes beyond showing what the specs describe, so no demo-server run or
`IPTV_*` switch is involved; verification is the App Store test export in CI and the worker.

## 1. Builds

- [x] 1.1 `build-appstore.sh` builds with `FERNSY_CLOUD=YES` (`NO` to build without) and checks each archive's `FernsyCloud` key
- [x] 1.2 `Info-TV.plist` gets the `FernsyCloud` key; a Release tvOS build shows `YES`
- [x] 1.3 `release.yml -f channel=appstore-test` on the branch: the three archives report "Fernsy Cloud: YES" (run 41299055234: all three "Fernsy Cloud: YES")

## 2. Server and website

- [x] 2.1 Deploy the production worker with the assistant relay and `OPENROUTER_API_KEY`; an unauthenticated request is refused, a request with an ended or missing subscription gets 402/401 (deployed 2026-11-01; unauthenticated requests 401, no dev access in production; the subscription refusals are covered by the worker tests, to keep test accounts out of the production database)
- [x] 2.2 Privacy pages (German, English): iCloud sync, Fernsy Cloud, assistant, transfers to the USA
- [x] 2.3 DEVELOPMENT.md: Fernsy Cloud on in App Store builds

## 3. Wrap-up

- [x] 3.1 `openspec validate --all --strict`

## Workflow follow-up

- Release-note trailers on the launch commit (users see Fernsy Cloud and the assistant). Merge
  into `main` and push with the user's consent (given 2026-11-01); the next release tag ships it.
