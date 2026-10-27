import SwiftUI
import UIKit

/// What a text entry holds: sets the keyboard, autofill and secure entry.
enum TVTextContent { case plain, url, username, password }

/// A text field drawn by Fernsy (tvos-text-fields): tvOS draws its own platter for a focused
/// `TextField` and ignores `.textFieldStyle(.plain)`. The focusable part is a button with the
/// caller's look; selecting it makes a hidden, unfocusable `UITextField` first responder, which
/// presents tvOS' text entry (keyboard, dictation, typing on a nearby iPhone).
struct TVTextEntry<Label: View>: View {
    @Binding var text: String
    var content: TVTextContent = .plain
    /// Shown on tvOS' keyboard screen while the text is empty.
    var prompt: String = ""
    @ViewBuilder let label: Label
    @State private var handle = TVTextEntryHandle()

    var body: some View {
        Button { handle.field?.becomeFirstResponder() } label: { label }
            .background {
                HiddenTextField(text: $text, content: content, prompt: prompt, handle: handle)
                    .frame(width: 1, height: 1)
            }
            .accessibilityValue(content == .password ? String(repeating: "•", count: text.count) : text)
    }
}

/// The sign-in forms' field: a card with a small label over the value, light while focused.
struct TVFormField: View {
    let label: LocalizedStringResource
    @Binding var text: String
    var content: TVTextContent = .plain

    var body: some View {
        TVTextEntry(text: $text, content: content, prompt: String(localized: label)) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.system(size: 18, weight: .semibold)).opacity(0.6)
                Text(verbatim: content == .password ? String(repeating: "•", count: text.count) : text)
                    .font(.system(size: 27, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        }
        .buttonStyle(TVTileStyle())
    }
}

@MainActor final class TVTextEntryHandle {
    weak var field: UITextField?
}

private struct HiddenTextField: UIViewRepresentable {
    @Binding var text: String
    let content: TVTextContent
    let prompt: String
    let handle: TVTextEntryHandle

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UnfocusableTextField {
        let field = UnfocusableTextField()
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.delegate = context.coordinator
        // Invisible but still able to become first responder (a hidden view cannot).
        field.alpha = 0
        handle.field = field
        return field
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UnfocusableTextField, context: Context) -> CGSize? {
        CGSize(width: 1, height: 1)
    }

    func updateUIView(_ field: UnfocusableTextField, context: Context) {
        context.coordinator.text = $text
        if field.text != text { field.text = text }
        field.placeholder = prompt
        field.isSecureTextEntry = content == .password
        field.keyboardType = content == .url ? .URL : .default
        field.textContentType = switch content {
        case .plain: nil
        case .url: .URL
        case .username: .username
        case .password: .password
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        @objc func changed(_ field: UITextField) { text.wrappedValue = field.text ?? "" }
        // Menu on tvOS' keyboard ends editing as "cancelled" and puts the old text back into a
        // UITextField; a SwiftUI TextField keeps what was typed, so the field does too.
        func textFieldDidEndEditing(_ field: UITextField) { field.text = text.wrappedValue }
        func textFieldShouldReturn(_ field: UITextField) -> Bool { field.resignFirstResponder() }
    }
}

/// Never takes the focus itself: the button in front of it does.
final class UnfocusableTextField: UITextField {
    override var canBecomeFocused: Bool { false }
    // SwiftUI sets these on hosted views; the button carries the identifier and value.
    override var isAccessibilityElement: Bool { get { false } set {} }
    override var accessibilityElementsHidden: Bool { get { true } set {} }
}
