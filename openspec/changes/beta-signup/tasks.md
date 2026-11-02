# Tasks

## 1. App Store Connect (user, with my help)

- [ ] 1.1 External TestFlight group "Public Beta" with the current Mac, iOS and tvOS builds; test information (description, feedback e-mail, demo sign-in); Beta App Review requested
- [ ] 1.2 Team API key with the App Manager role; `.p8`, key id and issuer in `~/.config/fernsy/` (mode 600); the group's id

## 2. Worker

- [ ] 2.1 `testflight.js`: ES256 JWT for the App Store Connect API, add tester to the group (409 counts as done); tests with a fake API
- [ ] 2.2 Route `POST /v1/beta/signup` with CORS, consent and hidden-field checks, rate limit per IP and address hash in D1 (pruned daily); README, `deploy.sh` secrets; dev deploy and a real sign-up into the group

## 3. Website

- [ ] 3.1 `beta.html` / `en/beta.html` with form, consent, confirmation and error states
- [ ] 3.2 Beta button on the home pages, beta link in the footers, privacy pages (Apple as recipient for TestFlight, rate-limit data for a day)

## 4. Verification and go-live

- [ ] 4.1 Sign-up end to end against the prod worker: the address appears under External Testers with name; same answer for a second sign-up; rate limit; `openspec validate --all --strict`
- [ ] 4.2 DEVELOPMENT.md; archive, merge into `main`, push
