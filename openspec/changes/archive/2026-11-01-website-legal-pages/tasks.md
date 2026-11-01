# Tasks

## 1. Pages

- [x] 1.1 Pricing pages `preise.html`, `en/pricing.html`
- [x] 1.2 Terms pages `agb.html`, `en/terms.html`
- [x] 1.3 Refund pages `erstattung.html`, `en/refunds.html`
- [x] 1.4 Privacy pages: Paddle for website purchases, Paddle.js on the checkout page
- [x] 1.5 Footers of every page link pricing, terms, refunds, privacy, imprint; the checkout pages link terms and refunds

## 2. Catalog and checks

- [x] 2.1 Live Paddle price 3.49 € monthly (quantity 1..1) on Fernsy Cloud (`pri_01m6c4cd7tfteh5ybbjqcda4gj`, in `~/.config/fernsy/paddle-live.json`), so the catalog matches the pricing page. Switching the prod worker's `PADDLE_PRICE_ID` to it moves to `cloud-pricing-100gb` 2.1 (setting the secret needs the user's permission)
- [x] 2.2 Pages render locally (desktop; the footer wraps by CSS on phones); links resolve; `openspec validate --all --strict`
- [x] 2.3 Merge into `main`, the pages answer 200 on www.fernsy.app

## Workflow follow-up

- The user enters the URLs in Paddle's website approval and has the texts reviewed.
