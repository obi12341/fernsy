# Tasks

Against the demo server (`IPTV_SERVER=https://fernsy-demo.mobilistics.workers.dev`, demo/demo)
and the dev services (`IPTV_CONTROL`, `IPTV_CLOUD`, `IPTV_CLOUDTOKEN`, see DEVELOPMENT.md ›
Fernsy Server); a refused login is a wrong password on the demo server.

## 1. Shared

- [ ] 1.1 FernsyShared: `ControlKind.login` and its value (credentials, sent at); `ControlServerStatus` gets the login's display form and the last login item's outcome; tests round-trip both with `swift test` (macOS and Linux)

## 2. Server

- [ ] 2.1 Apply a newer `login` item after checking it with the provider; keep the old login when refused, retry while unreachable (up to an hour); store it in `secrets.json`; report login and outcome in the status; `PlannerTests`-style unit test for the decision, and a run with `FernsyServer app-login` (debug stand-in) with demo/demo and with a wrong password against `fernsy-control-dev`

## 3. Apps

- [ ] 3.1 FernsyCore `ServerModel.useLogin(_:)` and the status fields; `ServerModelTests` with the fake control
- [ ] 3.2 Server settings on Mac, iPhone/iPad and Apple TV: "Records with: user @ host", "Use This Login", the refused notes; German and English strings; checked in `ServerUITests` (iOS) with the dev services and a running server (`TEST_RUNNER_FERNSY_SERVER_STATUS`)

## 4. Docs and verification

- [ ] 4.1 `server/README.md` (changing the login) and DEVELOPMENT.md › Fernsy Server
- [ ] 4.2 End to end: pair with demo/demo, send a wrong password (refused, recordings go on), send demo/demo again (accepted); `openspec validate --all --strict`

## Workflow follow-up

- Archive after `headless-recorder`; release-note trailers on the commits users notice; merge
  into `main` and push with the user's consent.
