## ADDED Requirements

### Requirement: Changing the server's IPTV login
The apps SHALL show which IPTV login a paired server records with (user name and provider,
never the password) and SHALL let the user hand the server the login the device uses, without
pairing again. The login SHALL reach the server encrypted so that only the user's devices and
the server can read it.

#### Scenario: Password changed at the provider
- **WHEN** the user changed the IPTV password, signed in again on the iPad and chooses "Use This Login" in the server's settings
- **THEN** the server records with the new password from its next recording on, and the settings show the login it uses

### Requirement: A refused login never replaces a working one
The server SHALL try a new login with the provider before taking it and SHALL keep its previous
login when the provider refuses it. The apps SHALL show a refused new login, and when the
provider refuses the login the server records with, they SHALL say so and offer to send the
device's login.

#### Scenario: Wrong login sent
- **WHEN** the iPad sends a login the provider refuses
- **THEN** the server keeps recording with its previous login and the settings say that the new login was refused

#### Scenario: Server's login refused
- **WHEN** the provider refuses the login the server records with
- **THEN** the server's settings on every device say so and offer "Use This Login"
