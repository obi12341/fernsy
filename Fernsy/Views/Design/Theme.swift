import AppKit
import SwiftUI

/// Colours of the redesign that are not system colours. The accent is `AccentColor` in the
/// asset catalog (violet from the app icon); everything else uses system colours, which
/// already follow the appearance and accessibility settings.
enum Theme {
    /// Recording and live only – never for selection or main actions.
    static let record = dynamic(light: 0xE0352C, dark: 0xFF4D45)
    /// Warnings and offline states.
    static let warning = dynamic(light: 0xB86E00, dark: 0xFFB340)
    /// Channel logo tiles stay graphite in both appearances: most IPTV logos are made for
    /// dark TV screens.
    static let logoTile = Color(hex: 0x2C2B33)
    /// For logos that are dark on a transparent background.
    static let logoTileLight = Color(hex: 0xE9E8EE)
    /// Outline of small tags (country, quality).
    static let tagBorder = Color.primary.opacity(0.18)
    static let online = dynamic(light: 0x2A9D57, dark: 0x4CD07D)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
}
