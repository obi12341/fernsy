# Design

## Context

On tvOS a SwiftUI `TextField`/`SecureField` is a focusable control that draws its own platter
(dark at rest, white when focused, lifted with a shadow). `.textFieldStyle(.plain)` removes it on
iOS and macOS, but not on tvOS. `FormField` (`SignInScreen.swift`) wraps that control in the
design's card, so both shapes show and both react to focus. The search fields
(`JellyfinSearchScreens.swift`, `AllCategoriesScreen.swift`) show the bare platter.

tvos-live design H keeps system text entry for the keyboard and the iPhone notification; this
change keeps that and only replaces what is drawn.

## Goals / Non-Goals

**Goals:**
- One shared component for all four places, drawn entirely by Fernsy.
- tvOS' keyboard screen, dictation and the iPhone typing notification keep working.
- Content types (`.URL`, `.username`, `.password`) stay, so iPhone autofill keeps working.

**Non-Goals:**
- Inline editing in the card (tvOS edits text on its keyboard screen anyway).

## Decisions

### A. A focusable card plus a hidden UIKit text field

The component is a `Button` drawn as the design's field (card, label, value or dots), so focus,
lift and colours come from our own style. Behind it sits a `UITextField` in a
`UIViewRepresentable`, alpha almost 0 and not focusable (`canBecomeFocused` false). The button's
action calls `becomeFirstResponder()` on it, which presents tvOS' text entry for that field with
its keyboard type, content type and secure entry; the iPhone notification is tied to the first
responder, not to the focus. Edits go back to the binding through the field's delegate/target, and
the keyboard's Done or Menu ends editing and returns focus to the card.

Rejected:
- **Dropping our card and keeping the system field** (option A in the discussion): clean, but
  not the design.
- **Restyling the system field** (UIKit `borderStyle = .none` or SwiftUI modifiers): tvOS still
  draws its focus look for a focused text field; removing it needs its private view hierarchy,
  which breaks between tvOS versions.
- **A focus-redirect to a hidden SwiftUI `TextField`**: focusing a field does not open the
  keyboard (that needs a select press on it), and a hidden focusable view confuses the focus
  engine's movement.
- **A custom keyboard**: already rejected in tvos-live (design H); it would lose the iPhone
  notification.

### B. Accessibility and tests

The card carries the field's identifier (`signin.server`, `search.field`, …) and its value as
accessibility value (dots for the password). UI tests focus the card, press select, type with
`app.typeText` into the presented entry and read the value from the card. The hidden field gets
no identifier, so queries keep finding one element per id.

### C. Search fields use the same component

The search field under the letter row keeps its hint text ("Dictate with the Siri button or type
on your iPhone") as the card's empty state, drawn as the design's hint line; the categories
search keeps its magnifying-glass capsule. Both use the component with a different look, so the
hidden-field mechanics live in one place.

### D. Findings while building it

- Pitfall: tvOS ignores `.textFieldStyle(.plain)`; a focused SwiftUI `TextField` always draws
  its own platter.
- `becomeFirstResponder()` on the hidden, unfocusable field presents tvOS' keyboard screen with
  the prompt, secure entry and content type; `.editingChanged` fires per character.
- Pitfall: Menu on that keyboard ends editing as cancelled and puts the old text back into a
  `UITextField` (a SwiftUI `TextField` keeps what was typed). The component keeps the last
  typed value: the binding follows `.editingChanged`, and `textFieldDidEndEditing` writes the
  binding back into the field.
- The hidden field is no accessibility element (overridden getters, since SwiftUI sets them on
  hosted views), so VoiceOver reads only the card. XCUITest still lists it as a `TextField` with
  the card's identifier; tests query the card as `app.buttons[...]`.
- Search: the line under the letter row is now as wide as its text, centred; the results are a
  focus section so Down still reaches the first hit on the left.
- The hidden field needs `alpha = 0` on the UIKit view and a fixed `sizeThatFits`: with only
  SwiftUI's `.opacity` and `.frame` its text showed faintly through the card at its own size.
  `alpha = 0` (not `isHidden`) keeps it able to become first responder.
- All Categories: Up from the chips did not reach the search capsule on the right (with the old
  system field as well); the header is now a focus section.
- Siri dictation on the focused search card cannot be checked in the simulator (XCUIRemote has
  no Siri button); it is listed for the real Apple TV.

## Risks / Trade-offs

- [`becomeFirstResponder()` on a near-invisible field may not present the keyboard on some tvOS
  version] → First task is a spike in the simulator; if it fails, fall back to the system field
  without our card (rejected option A) and tell the user before going on.
- [Siri dictation used to work by holding the Siri button while the system field had focus] →
  Dictation still works on the keyboard screen; check whether holding Siri on the focused card
  still dictates, and note it in the spec's search scenario if not.
- [The iPhone notification cannot be tested in the simulator] → Check that the field becomes
  first responder with the content type set; the real-device check is listed for the user.
