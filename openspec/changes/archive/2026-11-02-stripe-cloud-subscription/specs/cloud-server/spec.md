## MODIFIED Requirements

### Requirement: Subscription check
The server SHALL decide whether a subscription is active only from the provider that sold it
(Apple's server API and notifications, Stripe's signed webhooks and API), never from a client's
claim alone. An Apple subscription SHALL be linked to the account named by the transaction's app
account token, any other only on an explicit move; a Stripe subscription to the account it was
created for. An account SHALL count as subscribed while either provider's subscription is.

#### Scenario: Renewal
- **WHEN** Apple notifies a renewal for a user's subscription
- **THEN** the user's subscription is active until the new expiry without the app doing anything

#### Scenario: Subscription of another account
- **WHEN** an account presents a transaction whose app account token names another account
- **THEN** the server refuses to link it and the other account's link stays

#### Scenario: Refund
- **WHEN** Apple notifies a refund
- **THEN** the subscription counts as ended from that moment

#### Scenario: Transaction id alone
- **WHEN** a request names a valid transaction id of someone else's purchase made for another account
- **THEN** the server does not link it to the requesting account

#### Scenario: Website subscription renewal and cancellation
- **WHEN** Stripe notifies that an account's subscription renewed, and later that it was canceled at the end of the period
- **THEN** the account stays active until the end of the paid period and then ends, with the usual grace period for its recordings

#### Scenario: Forged notification
- **WHEN** a request to the Stripe notification route carries no valid Stripe signature
- **THEN** the server rejects it and no subscription changes

## REMOVED Requirements

### Requirement: Managing a Paddle subscription
**Reason**: Paddle refused the account; website purchases go through Stripe.
**Migration**: "Managing a website subscription" below; only Paddle sandbox test subscriptions existed.

## ADDED Requirements

### Requirement: Managing a website subscription
For an account with a Stripe subscription, the server SHALL return a short-lived link to Stripe's
customer portal for it, where the user updates payment details, downloads invoices and cancels.
The server SHALL store only Stripe's customer and subscription ids for the account, no e-mail
address or payment details.

#### Scenario: Manage from the DMG
- **WHEN** a Stripe subscriber chooses "Manage Subscription" in the DMG
- **THEN** Stripe's customer portal opens for their subscription without a login
