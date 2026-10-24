## MODIFIED Requirements

### Requirement: Edit mode
Live TV SHALL have an "Edit" toolbar button. In Edit mode, every category and channel has a
checkbox (checked = shown); hidden ones stay in their usual place, dimmed and labelled
"Ausgeblendet". "Show All" unhides everything at once, "Done" leaves Edit mode. Adult
categories have no checkbox in Edit mode and point to Settings › Youth protection.
Entering Edit mode while the guide is shown switches to the list.

#### Scenario: Showing a hidden channel again
- **WHEN** the user clicks Edit, then the checkbox of a dimmed channel, then Done
- **THEN** the channel is listed normally again

#### Scenario: Edit mode in the guide
- **WHEN** the guide is shown and the user clicks Edit
- **THEN** Live TV switches to the list with hidden items visible and dimmed

#### Scenario: Showing everything again
- **WHEN** the user clicks "Show All" in Edit mode
- **THEN** all hidden categories and channels are shown again
