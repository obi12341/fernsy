## MODIFIED Requirements

### Requirement: Allowance and its end
The assistant SHALL be limited to 300 requests per subscription and calendar month and a
short-term rate. Settings › Fernsy Cloud SHALL show the requests used this month. When the
allowance is used up or the subscription is not active, the assistant SHALL say so and when it is
available again, instead of answering.

#### Scenario: Allowance used up
- **WHEN** the user has used all 300 requests of the month and asks again
- **THEN** the assistant says the monthly requests are used up and the date they renew

#### Scenario: Without subscription
- **WHEN** a user without an active subscription opens the assistant
- **THEN** it offers Fernsy Cloud and sends nothing
