import AppKit
import SwiftUI

/// A channel logo on a 13:8 tile: graphite in both appearances (IPTV logos are mostly made
/// for dark screens), light for logos that are dark on a transparent background, initials
/// when there is no logo.
struct LogoTile: View {
    let url: String?
    let name: String
    var width: CGFloat = 52

    @State private var image: NSImage?
    @State private var tone: LogoTone?

    private var height: CGFloat { (width * 8 / 13).rounded() }

    var body: some View {
        RoundedRectangle(cornerRadius: max(5, width * 0.13), style: .continuous)
            .fill(tone == .darkOnClear ? Theme.logoTileLight : Theme.logoTile)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(width * 0.12)
                } else {
                    Text(Self.initials(of: name))
                        .font(.system(size: width * 0.27, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 4)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: max(5, width * 0.13), style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
            .frame(width: width, height: height)
            .task(id: url) { await load() }
            .accessibilityLabel(name)
    }

    private func load() async {
        guard let url, let parsed = URL(string: url) else {
            image = nil
            tone = nil
            return
        }
        let pixels = Int(width * 3)
        if let hit = ImagePipeline.shared.cached(parsed, maxPixel: pixels) {
            image = hit
            tone = ImagePipeline.shared.tone(for: parsed)
            return
        }
        image = nil
        tone = nil
        let loaded = await ImagePipeline.shared.image(parsed, maxPixel: pixels)
        image = loaded
        tone = loaded == nil ? nil : ImagePipeline.shared.tone(for: parsed)
    }

    /// "Kanal Süd" → "KS", "Nordlicht 1" → "N1", "Entdecker" → "EN".
    static func initials(of name: String) -> String {
        let words = name.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !words.isEmpty else { return String(name.prefix(2)).uppercased() }
        if words.count == 1 { return String(words[0].prefix(2)).uppercased() }
        return words.prefix(3).compactMap(\.first).map { String($0) }.joined().uppercased()
    }

    #if DEBUG
    /// IPTV_LOGOTONETEST=1: tone classification on generated logos and the initials rule.
    static func selfTest() {
        func sample(_ draw: (CGContext) -> Void) -> NSImage {
            let context = CGContext(data: nil, width: 64, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            draw(context)
            return NSImage(cgImage: context.makeImage()!, size: NSSize(width: 64, height: 40))
        }
        let text = CGRect(x: 8, y: 12, width: 48, height: 16)
        let whiteOnClear = sample { $0.setFillColor(.white); $0.fill(text) }
        let blackOnClear = sample { $0.setFillColor(.black); $0.fill(text) }
        let opaque = sample { $0.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.4, alpha: 1)); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 40)) }
        let cases: [(String, Bool)] = [
            ("white on clear → graphite", ImagePipeline.measureTone(whiteOnClear) == .other),
            ("black on clear → light", ImagePipeline.measureTone(blackOnClear) == .darkOnClear),
            ("opaque dark → graphite", ImagePipeline.measureTone(opaque) == .other),
            ("initials KS", initials(of: "Kanal Süd") == "KS"),
            ("initials N1", initials(of: "Nordlicht 1") == "N1"),
            ("initials EN", initials(of: "Entdecker") == "EN"),
        ]
        for (name, ok) in cases { debugLog("[test] logo tile \(ok ? "pass" : "FAIL"): \(name)") }
    }
    #endif
}
