import SwiftUI

/// Colors and focus styles of the Apple TV design (Claude Design, `AppleTV.dc.html`). The
/// design is drawn at 1920×1080, which is the Apple TV's size in points, so its pixel values
/// are used as points.
enum TVTheme {
    static let background = Color(hex: 0x111015)
    static let text = Color(hex: 0xF3F2F7)
    static let secondary = Color(hex: 0xEBE9F5).opacity(0.72)
    static let tertiary = Color(hex: 0xEBE9F5).opacity(0.5)
    /// A focused tile or row: light, with dark text.
    static let focused = Color(hex: 0xF3F2F7)
    static let focusedText = Color(hex: 0x18171C)
    static let tile = Color.white.opacity(0.07)
    static let accent = Color(hex: 0x5B53E0)
    static let accentLight = Color(hex: 0x958FFF)
    static let accentSoft = Color(hex: 0xB7B3FF)
    static let live = Color(hex: 0xFF3B30)
    static let favorite = Color(hex: 0xFFCC4D)
    static let warning = Color(hex: 0xFFB340)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// The design's focus look for tiles and rows: light background and dark text, slightly larger
/// with a shadow while focused; `rest` is the background without focus.
struct TVTileStyle: ButtonStyle {
    var rest: Color = TVTheme.tile
    var radius: CGFloat = 18
    var scale: CGFloat = 1.05

    func makeBody(configuration: Configuration) -> some View {
        TVTile(configuration: configuration, rest: rest, radius: radius, scale: scale)
    }

    private struct TVTile: View {
        let configuration: Configuration
        let rest: Color
        let radius: CGFloat
        let scale: CGFloat
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundStyle(focused ? TVTheme.focusedText : TVTheme.text)
                .background(focused ? TVTheme.focused : rest, in: .rect(cornerRadius: radius))
                .scaleEffect(focused ? scale : 1)
                .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: 20, y: 20)
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// The design's pill buttons ("Anmelden", "Demo-Zugang testen").
struct TVPillStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, prominent: prominent)
    }

    private struct Pill: View {
        let configuration: Configuration
        let prominent: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(.system(size: 28, weight: prominent ? .semibold : .medium))
                .padding(.horizontal, prominent ? 48 : 36)
                .frame(height: 80)
                .foregroundStyle(focused ? TVTheme.focusedText : prominent ? TVTheme.text : TVTheme.text.opacity(0.75))
                .background(focused ? TVTheme.focused : Color.white.opacity(prominent ? 0.16 : 0.08), in: .capsule)
                .scaleEffect(focused ? 1.06 : 1)
                .shadow(color: .black.opacity(focused ? 0.35 : 0), radius: 12, y: 10)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}
