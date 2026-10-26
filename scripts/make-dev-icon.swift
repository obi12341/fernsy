// Renders the debug build's icon (AppIcon-Dev) from AppIcon: the same picture with an orange
// "DEV" band, so "Fernsy Dev" is told apart from the installed app in the Dock and Finder.
// Usage: swift scripts/make-dev-icon.swift (again whenever AppIcon changes)
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("Fernsy/Assets.xcassets")
let source = assets.appendingPathComponent("AppIcon.appiconset")
let output = assets.appendingPathComponent("AppIcon-Dev.appiconset")

try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try FileManager.default.copyItem(at: source.appendingPathComponent("Contents.json"),
                                 to: output.appendingPathComponent("Contents.json"))

let files = try FileManager.default.contentsOfDirectory(atPath: source.path).filter { $0.hasSuffix(".png") }
for name in files {
    guard let image = NSImage(contentsOf: source.appendingPathComponent(name)),
          let original = image.representations.first else { continue }
    let width = original.pixelsWide, height = original.pixelsHigh
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(width)
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    image.draw(in: canvas)

    // The icon body leaves a margin of about 10 % (macOS icon grid); the band spans it.
    let inset = size * 0.1
    let band = NSRect(x: inset, y: inset + size * 0.06, width: size - inset * 2, height: size * 0.2)
    NSColor(srgbRed: 1, green: 0.55, blue: 0.1, alpha: 1).setFill()
    NSBezierPath(roundedRect: band, xRadius: size * 0.03, yRadius: size * 0.03).fill()
    let text = NSAttributedString(string: "DEV", attributes: [
        .font: NSFont.systemFont(ofSize: band.height * 0.72, weight: .black),
        .foregroundColor: NSColor.white,
    ])
    let textSize = text.size()
    text.draw(at: NSPoint(x: band.midX - textSize.width / 2, y: band.midY - textSize.height / 2))
    NSGraphicsContext.restoreGraphicsState()

    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
print("wrote \(files.count) images to \(output.path)")
