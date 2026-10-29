// Renders the iPhone and iPad app's icons into FernsyiOS/Assets.xcassets from the Mac icon:
// the Mac icon's body full bleed on its indigo background (iOS rounds the corners itself), as
// "AppIcon" and, with the orange "DEV" band of make-dev-icon.swift, "AppIcon-Dev".
// Usage: swift scripts/make-ios-icons.swift (again whenever AppIcon changes)
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let macIcon = root.appendingPathComponent("Fernsy/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
let catalog = root.appendingPathComponent("FernsyiOS/Assets.xcassets")
guard let source = NSImage(contentsOf: macIcon) else { fatalError("missing \(macIcon.path)") }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

func icon(dev: Bool) -> Data {
    let size = 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = NSRect(x: 0, y: 0, width: size, height: size)
    NSGradient(colors: [rgb(28, 30, 78), rgb(64, 44, 140), rgb(40, 92, 176)])!.draw(in: r, angle: -60)
    // The Mac icon's body (824 px of 1024, macOS grid) filling the canvas: its corner radius is
    // smaller than the iOS mask's, so the mask hides its corners.
    let scale = source.size.width / 1024
    let crop = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    source.draw(in: r, from: crop, operation: .sourceOver, fraction: 1)
    if dev {
        let band = NSRect(x: 0, y: CGFloat(size) * 0.06, width: CGFloat(size), height: CGFloat(size) * 0.2)
        NSColor(srgbRed: 1, green: 0.55, blue: 0.1, alpha: 1).setFill()
        NSBezierPath(rect: band).fill()
        let text = NSAttributedString(string: "DEV", attributes: [
            .font: NSFont.systemFont(ofSize: band.height * 0.72, weight: .black), .foregroundColor: NSColor.white,
        ])
        let textSize = text.size()
        text.draw(at: NSPoint(x: band.midX - textSize.width / 2, y: band.midY - textSize.height / 2))
    }
    NSGraphicsContext.restoreGraphicsState()
    // Opaque: the App Store rejects iOS icons with an alpha channel (AppKit cannot draw into
    // an alpha-less bitmap, so the picture is copied into one).
    let opaque = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    opaque.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: size, height: size))
    return NSBitmapImageRep(cgImage: opaque.makeImage()!).representation(using: .png, properties: [:])!
}

for (name, dev) in [("AppIcon", false), ("AppIcon-Dev", true)] {
    let dir = catalog.appendingPathComponent("\(name).appiconset")
    try? FileManager.default.removeItem(at: dir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try icon(dev: dev).write(to: dir.appendingPathComponent("icon-1024.png"))
    let contents = """
    {
      "images" : [ { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
    try contents.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
print("wrote AppIcon and AppIcon-Dev to \(catalog.path)")
