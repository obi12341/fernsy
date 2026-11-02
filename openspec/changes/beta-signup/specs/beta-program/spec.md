## Purpose

The public beta of Fernsy through TestFlight: people sign up on fernsy.app and become external
testers in App Store Connect, invited by Apple to the iPhone, iPad, Apple TV and Mac betas.

## ADDED Requirements

### Requirement: Sign-up becomes an external tester
A sign-up on the beta page SHALL add the given e-mail address, with the optional first and last
name, as an external tester to the public TestFlight group of Fernsy through the App Store Connect
API, so that Apple sends the invitation and the tester appears by name and address under External
Testers. The sign-up SHALL require the visitor's consent to this processing.

#### Scenario: Sign-up
- **WHEN** a visitor enters their e-mail address and name, agrees, and sends the form
- **THEN** the page confirms that an invitation from Apple (TestFlight) is on its way, and the address appears in the public group under External Testers in App Store Connect

#### Scenario: Without consent
- **WHEN** the consent box is not ticked
- **THEN** nothing is sent and the page asks for the consent

### Requirement: Sign-up without leaking or abuse
The server SHALL give the same confirmation whether the address was new or already a tester, SHALL
refuse sign-ups from the form's hidden bot field, and SHALL accept at most a few sign-ups per hour
from one IP address and per e-mail address. It SHALL keep nothing about a sign-up except what the
rate limit needs, for at most a day.

#### Scenario: Address already a tester
- **WHEN** someone signs up with an address that is already in the group
- **THEN** the page shows the same confirmation as for a new address

#### Scenario: Many sign-ups from one place
- **WHEN** one IP address sends a sixth sign-up within an hour
- **THEN** the server refuses it and the page asks to try again later
