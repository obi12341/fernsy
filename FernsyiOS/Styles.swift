import SwiftUI

/// The pill buttons of the player's cards on touch screens (the Apple TV's `ActionButtonStyle`
/// lives with its screens; the shared status layer uses this one on iOS).
struct ActionButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 22)
            .frame(height: 44)
            .foregroundStyle(prominent ? TVTheme.focusedText : TVTheme.text)
            .background(prominent ? TVTheme.focused : Color.white.opacity(0.16), in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
