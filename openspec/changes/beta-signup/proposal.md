# Proposal

## Why

The first App Store version is still in review, while Fernsy already runs on Mac, iPhone, iPad and
Apple TV. A public beta through TestFlight lets people use the iPhone, iPad and Apple TV apps now,
takes pressure off the App Store release, and gives the website something to promote. The user
wants every beta tester listed by name and e-mail under External Testers in App Store Connect, not
anonymous testers from a public link.

## What Changes

- A beta page on fernsy.app (`beta.html`, `en/beta.html`) with a sign-up form: e-mail address,
  optional first and last name, consent to the processing; linked from the home page next to the
  DMG download.
- A route on the Fernsy Cloud worker that adds the address as a beta tester to a TestFlight group
  through the App Store Connect API; Apple then invites the tester by e-mail.
- Protection against abuse: a hidden field for bots, a rate limit per IP and per address, and no
  answer that reveals whether an address is already a tester.
- The privacy pages describe the sign-up (Apple as recipient, what is stored and for how long).

Out of scope: a newsletter or launch mailing list, our own confirmation e-mails, beta builds of
the DMG (the website's DMG is already public), managing testers from the website.

## Capabilities

### New Capabilities

- `beta-program`: the public beta through TestFlight: sign-up on the website and how a sign-up
  becomes an external tester.

### Modified Capabilities

- `website`: the page set grows by the beta page, linked from the home page; the privacy statement
  covers the sign-up.

## Impact

- `website/`: new `beta.html`, `en/beta.html`, home pages, privacy pages, footers.
- `cloud-server/`: `testflight.js` (App Store Connect API token, add tester), route
  `POST /v1/beta/signup` with CORS, rate limit in D1, tests; `deploy.sh` secrets
  (`ASC_KEY`, `ASC_KEY_ID`, `ASC_ISSUER`, `BETA_GROUP_ID`).
- App Store Connect (user): an external TestFlight group "Public Beta", builds assigned to it,
  Beta App Review of the first build per version, a team API key with the App Manager role.
- DEVELOPMENT.md.
