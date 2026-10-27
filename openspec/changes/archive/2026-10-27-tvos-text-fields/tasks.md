# Tasks

## 1. Spike

- [x] 1.1 In the simulator (`scripts/tv-run.sh`, demo account), check that a button calling `becomeFirstResponder()` on a near-invisible, non-focusable `UITextField` opens tvOS' keyboard with the field's content type and secure entry, that typed text reaches the binding, and that Done/Menu returns focus to the button. If not, stop and report (design, risks).

## 2. Component

- [x] 2.1 Add the shared text-entry component under `FernsyTV/` (button drawn by Fernsy, hidden `UITextField` bridge, keyboard type, content type, secure entry, accessibility identifier and value).
- [x] 2.2 Sign-in card look: label over the value, dots for a password, light and lifted on focus, as in the design.
- [x] 2.3 Hint-line look for the search field and capsule look with magnifying glass for the categories search.

## 3. Screens

- [x] 3.1 IPTV sign-in form: replace `FormField` with the component; keep Down from the password to "Sign In".
- [x] 3.2 Jellyfin sign-in form: same.
- [x] 3.3 Search: the field under the letter row uses the component; the letter row and the results are unchanged.
- [x] 3.4 All Categories: the search capsule uses the component.
- [x] 3.5 German translations for any new or changed string in the TV string catalog.

## 4. Tests and verification

- [x] 4.1 Update `SignInUITests`, `JellyfinSignInUITests`, `SearchUITests` (and any categories-search test) to focus the card, select, type and read the card's value.
- [x] 4.2 Run `scripts/tv-uitest.sh` against the demo server (Jellyfin tests with `scripts/jellyfin-test-server.sh`, removed afterwards); all green.
- [x] 4.3 Simulator screenshots (`xcrun simctl io <id> screenshot`) of both sign-in forms at rest and focused, the search field and the categories search, compared with Claude Design `AppleTV.dc.html`; no system platter visible.
- [x] 4.4 Check whether holding the Siri button on the focused search card still dictates; record the result in design.md. (Not possible in the simulator; recorded, and moved to the real-device check below.)
- [x] 4.5 Record the pitfall (tvOS ignores `.textFieldStyle(.plain)`) in design.md.

## Workflow follow-up

- On a real Apple TV the user checks the iPhone typing notification on the sign-in fields and dictation with the Siri button on the focused search line.
- Archive with `/opsx:archive`, merge into `main`, push.
