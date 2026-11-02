# Design

## Context

Fernsy is one App Store Connect app record with Mac, iPhone/iPad and Apple TV builds (universal
purchase); every release tag uploads all three (`release.yml`). External testers in a TestFlight
group can install the builds assigned to the group on every platform. The first build of a version
for external testers needs Apple's Beta App Review. The Fernsy Cloud worker already serves CORS
routes for fernsy.app (`/v1/checkout/*`) and keeps small per-key counters in D1.

## Goals / Non-Goals

**Goals:** a sign-up that ends with the tester listed by name and address in App Store Connect and
Apple's invitation in their inbox, without a mailing list of our own.

**Non-Goals:** confirmation e-mails of our own (no mail service), a newsletter, removing testers.

## Decisions

### 1. App Store Connect API instead of a public TestFlight link
The worker calls `POST /v1/betaTesters` with the address, names and the public group
(`relationships.betaGroups`), authenticated with an ES256 JWT from a team API key. Apple invites
the tester and lists them in the group.
Rejected: the public TestFlight link (testers join anonymously, the user wants them listed by
person); a sign-up list exported by hand (slow, and we would keep personal data).

### 2. A route on the Fernsy Cloud worker
`POST /v1/beta/signup` (CORS for fernsy.app and `CHECKOUT_ORIGINS`) with `{email, firstName,
lastName, consent, website}` (`website` is the hidden bot field). `testflight.js` signs the token
(20 minutes, audience `appstoreconnect-v1`) with `ASC_KEY` / `ASC_KEY_ID` / `ASC_ISSUER` and adds
the tester to `BETA_GROUP_ID`. A 409 from Apple (already a tester) answers like success.
Rejected: a separate worker (a second deploy and set of secrets for one route); reusing the App
Store Server API key `APPSTORE_KEY` (a different key type, it cannot manage testers).

### 3. Key with the App Manager role
The API key needs the right to manage testers; App Manager is enough. The CI's Admin key stays in
CI only.
Rejected: the Admin key in the worker (more rights than the route needs).

### 4. Abuse
Hidden field, rate limit (5 per hour per IP and per SHA-256 of the address, in D1, pruned by the
daily cleanup), the same answer for new and known addresses. Someone could still sign up another
person's address; Apple's invitation is the only effect, and the person ignores it.
Rejected: Cloudflare Turnstile for now (an external script and another service in the privacy
statement; can come later if bots appear); a double opt-in (needs our own e-mail sending).

### 5. Pages
`beta.html` / `en/beta.html` in the site's text-page style: what the beta is (iPhone, iPad, Apple
TV, also Mac through TestFlight), what testers should know (beta builds, feedback through
TestFlight, the demo account if they have no provider), the form, the consent text, the
confirmation. The home pages get a second button next to the DMG download.

## Risks / Trade-offs

- [Beta App Review for each new version] → Builds reach testers only after it; the page says
  invitations may take a while.
- [Group limit of 10,000 external testers] → Far away; the route answers "full" if Apple refuses.
- [Apple refuses the beta like the App Store review] → The sign-up still works; the page states
  that builds follow once Apple approves the beta.

## Migration Plan

1. User: TestFlight group "Public Beta" (external), the current builds assigned, Beta App Review
   requested; a team API key with the App Manager role, its .p8 in `~/.config/fernsy/`.
2. Worker with the route and secrets, dev then prod; pages; merge.
