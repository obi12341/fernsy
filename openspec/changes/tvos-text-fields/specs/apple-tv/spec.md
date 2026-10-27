## ADDED Requirements

### Requirement: Text fields on Apple TV
Text fields in the Apple TV app (the sign-in forms, the search field and the categories search)
SHALL look as in the design and show no system field platter: a sign-in field is a card with its
label over the value, the password as dots and the label alone when empty, and lifts and turns
light on focus. Selecting a field SHALL open tvOS' text entry (keyboard, dictation, typing on a
nearby iPhone) and the entered text SHALL show in the field afterwards.

#### Scenario: Focusing a sign-in field
- **WHEN** the focus moves to "Server Address" on the IPTV sign-in form
- **THEN** the field's card lifts and turns light, and no second shape or white bar appears inside it

#### Scenario: Entering a value
- **WHEN** the user selects "Username", types "demo" and returns
- **THEN** the card shows "demo" under its label

#### Scenario: Password stays hidden
- **WHEN** a password has been entered
- **THEN** the field shows dots, not the password

#### Scenario: Typing on the iPhone
- **WHEN** the user selects a sign-in field while an iPhone is nearby
- **THEN** the iPhone offers to type into it, as with a system text field

#### Scenario: Search field
- **WHEN** the user moves down from the letter row to the search field and selects it
- **THEN** tvOS' text entry opens, and the query typed there updates the results
