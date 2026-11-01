## MODIFIED Requirements

### Requirement: Subscription check
The server SHALL decide whether a user's subscription is active only from the provider that sold
it – Apple's App Store Server API and Server Notifications, or Paddle's signed webhooks and API –
never from a client's claim alone. An Apple subscription SHALL be linked to the account whose id
Apple reports as the transaction's app account token; a transaction without that token, or with
another account's, SHALL be linked only when the request explicitly asks to move it. A Paddle
subscription SHALL be linked to the account named in its custom data. An account's subscription
SHALL count as active when a subscription from either provider is.

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

#### Scenario: Paddle renewal and cancellation
- **WHEN** Paddle notifies that an account's subscription renewed, and later that it was canceled at the end of the period
- **THEN** the account stays active until the end of the paid period and then ends, with the usual grace period for its recordings

#### Scenario: Forged notification
- **WHEN** a request to the Paddle notification route carries no valid Paddle signature
- **THEN** the server rejects it and no subscription changes

## ADDED Requirements

### Requirement: Managing a Paddle subscription
For an account with a Paddle subscription, the server SHALL return a short-lived, authenticated
link to Paddle's customer portal for it, where the user updates payment details, downloads
invoices and cancels. The server SHALL store only Paddle's customer and subscription ids for the
account, no e-mail address or payment details.

#### Scenario: Manage from the DMG
- **WHEN** a Paddle subscriber chooses "Manage Subscription" in the DMG
- **THEN** Paddle's customer portal opens signed in to their subscription without a login
