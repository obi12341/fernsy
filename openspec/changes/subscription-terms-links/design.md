# Design

## Context

- **The rejection.** App Review stopped iOS 2.3.0 automatically: no link to the Terms of Use in
  the metadata.
- **What the offers show today.**
  - iOS: `CloudSettingsView` shows `CloudOfferParts`, "name · price" (when StoreKit loaded the
    offer), "Subscribe" and "Restore Purchases".
  - iOS assistant (`AssistantSheet`), Apple TV settings (`SettingsScreen`) and Apple TV assistant
    (`AssistantOverlay`, "Subscribe · price"): the same in their own layout.
  - Mac: `CloudEnableSheet` and the assistant window. The DMG has its verbatim Stripe texts
    (`CloudEnableSheet.directText`).

  No offer shows the length, the renewal or any link.
- **Where the offer data comes from.** `CloudModel.offer` has `name` and `price`; StoreKit's
  product carries `subscription.subscriptionPeriod`. Privacy pages: `fernsy.app/datenschutz.html`
  and `/en/privacy.html`. Terms for the DMG: `agb.html` and `/en/terms.html`.

## Goals / Non-Goals

**Goals:** every offer meets guideline 3.1.2, on all platforms and in both languages, and the
descriptions carry the links, so 2.3.1 passes.

**Non-Goals:** a custom EULA, new website terms, a redesign of the offers.

## Decisions

### 1. One shared terms block, drawn per platform
FernsyCore gets `CloudTerms`:
- the renewal sentence (App Store: "Renews monthly until cancelled. Cancel at least 24 hours
  before the end of the period in your Apple account settings.";
  DMG: renewal and cancellation as on fernsy.app);
- the Terms URL (Apple standard EULA, or `fernsy.app/agb.html` / `en/terms.html` for
  `DIRECT_DISTRIBUTION`);
- the privacy URL in the app's language.

Each platform draws it under its offer:
- Mac and iOS: two `Link`s;
- Apple TV: the two addresses as `Text`, since tvOS has no browser.

The length comes from the product's subscription period ("1 month"). The price line becomes
"Fernsy Cloud · 1 month · 3,49 €". The strings live in FernsyCore's catalog (German included).

Rejected:
- **Hard-coding the texts in six views:** they would drift.
- **A QR code on the Apple TV:** Apple accepts the addresses as text, and the privacy policy text
  is in App Store Connect too.

### 2. Apple's standard EULA, not our own terms, for App Store sales
The user chose Apple's standard EULA. Our terms on fernsy.app are written for the website sale
through Stripe (withdrawal, payment, cancellation by e-mail) and do not fit a purchase through
Apple.

Rejected:
- **Our terms as a custom EULA in App Store Connect:** they would need rewriting for Apple's
  billing, and that is a legal review.

### 3. Store descriptions end with a subscription block
German and English, iOS, tvOS and Mac, for example:

```
FERNSY CLOUD
Monthly, auto-renewing subscription. Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://www.fernsy.app/en/privacy.html
```

It is checked by `check-store-texts.py` for length, and pasted in App Store Connect for 2.3.1.

### 4. Release 2.3.1, then resubmit
2.3.0's builds lack the links, so they cannot pass. A tag `v2.3.1` uploads new builds for all
three platforms. iOS 2.3.1 goes in with the subscription and its group, tvOS 2.3.1 alone. The Mac
1.0 stays in its review.

## Risks / Trade-offs

- **Price loading.** StoreKit may load the price late or not at all, for example offline. The
  offer then shows name, length and the renewal note without a price, as today. "Subscribe" opens
  Apple's sheet, which shows the price.
- **tvOS 2.3.0 in review.** It is likely to hit the same rule. It is replaced by 2.3.1 (taken out
  of review when 2.3.1 is ready).
