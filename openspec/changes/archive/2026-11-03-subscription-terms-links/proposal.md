# Proposal

## Why

App Review stopped iOS 2.3.0 (submission `ed37144f`, 2 Nov 2026). It offers the auto-renewable
subscription "Fernsy Cloud monthly", but has no functional link to the Terms of Use (EULA) in the
product page's metadata. Apple's rule for subscriptions (guideline 3.1.2) also asks the app itself
to show these things where it sells the subscription:
- the subscription's title, length and price;
- that it renews automatically;
- links to the Terms of Use and the privacy policy.

The offers in Fernsy show only the benefits and "Subscribe". Fixing only the metadata would get
the next build turned down for the missing links in the app.

## What Changes

- **Subscription offers in all apps.** These are Settings › Fernsy Cloud and the assistant's
  offer on iPhone/iPad and Apple TV, and Settings › Recordings › Fernsy Cloud and the assistant
  window on the Mac. Each offer shows:
  - name, length and price (from StoreKit; in the DMG from the website offer);
  - the note that the subscription renews monthly until cancelled, and where to cancel;
  - a link "Terms of Use (EULA)" and a link "Privacy Policy".
- **The links.** App Store builds use Apple's standard EULA
  (`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`). The DMG uses our terms on
  fernsy.app, because it sells through Stripe. The privacy link goes to our privacy page in the
  app's language. The Apple TV cannot open web pages, so it shows the two addresses as text.
- **Store texts.** The App Store descriptions for iOS, tvOS and Mac (German and English) end with
  a short subscription note and both links. This is in `docs/app-store.md` and in App Store
  Connect.
- **Release.** A new release (tag `v2.3.1`) carries the builds. iOS and tvOS are submitted again
  with the subscription.

Out of scope:
- A custom EULA in App Store Connect.
- Changes to the website's terms.
- Price or plan changes.
- The Mac App Store submission of 1.0, which is still in review and sells no subscription.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `recording-cloud`: "Subscription" adds what every offer shows (price, length, renewal,
  Terms of Use and privacy links).
- `distribution`: "Store texts within limits" adds the subscription note with both links to
  every platform's description.

## Impact

- **iPhone/iPad:** `FernsyiOS/CloudViews.swift`, `FernsyiOS/AssistantSheet.swift`.
- **Apple TV:** `FernsyTV/Screens/SettingsScreen.swift`, `FernsyTV/Screens/AssistantOverlay.swift`.
- **Mac:** `Fernsy/Views/CloudViews.swift`, `Fernsy/Views/AssistantView.swift`.
- **Shared:** a shared description of the links and terms in FernsyCore (`CloudModel` or a new
  `CloudTerms`).
- **Strings:** the string catalogs (German translations).
- **Store texts:** `docs/app-store.md` (local), App Store Connect (descriptions, resubmission).
- **Tests:** a UI test per platform for the links; CI release `v2.3.1`.
