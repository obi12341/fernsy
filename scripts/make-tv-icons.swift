// Renders the Apple TV app's icons into FernsyTV/Assets.xcassets from the Mac icon:
// layered app icons (back: the indigo background, front: the Mac icon's body, so tvOS can
// tilt them apart) and the top shelf images, as "TVAppIcon" and, with the orange "DEV" band
// of make-dev-icon.swift, "TVAppIcon-Dev". A stand-in until the designed Apple TV icon exists.
// Usage: swift scripts/make-tv-icons.swift (again whenever AppIcon changes)
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let macIcon = root.appendingPathComponent("Fernsy/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
let catalog = root.appendingPathComponent("FernsyTV/Assets.xcassets")
guard let source = NSImage(contentsOf: macIcon) else { fatalError("missing \(macIcon.path)") }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

func png(width: Int, height: Int, draw: (NSRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func background(_ r: NSRect) {
    NSGradient(colors: [rgb(38, 30, 92), rgb(72, 58, 168)])!.draw(in: r, angle: 60)
}

/// The Mac icon's body (the macOS grid's 824 px square of 1024), centred at `height`.
func motif(in r: NSRect, height: CGFloat) {
    let crop = NSRect(x: 100, y: 100, width: 824, height: 824)
    let scale = source.size.width / 1024
    let from = NSRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale, height: crop.height * scale)
    let target = NSRect(x: r.midX - height / 2, y: r.midY - height / 2, width: height, height: height)
    source.draw(in: target, from: from, operation: .sourceOver, fraction: 1)
}

func devBand(in r: NSRect) {
    let band = NSRect(x: r.minX, y: r.minY + r.height * 0.06, width: r.width, height: r.height * 0.2)
    rgb(255, 140, 26).setFill()
    NSBezierPath(rect: band).fill()
    let text = NSAttributedString(string: "DEV", attributes: [
        .font: NSFont.systemFont(ofSize: band.height * 0.72, weight: .black), .foregroundColor: NSColor.white,
    ])
    let size = text.size()
    text.draw(at: NSPoint(x: band.midX - size.width / 2, y: band.midY - size.height / 2))
}

func write(_ json: String, to dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

let info = #""info" : { "author" : "xcode", "version" : 1 }"#

/// An imagestack (front over back) at `size` points, in the given scales.
func imagestack(_ dir: URL, size: (Int, Int), scales: [Int], dev: Bool) throws {
    try write("{ \(info), \"layers\" : [ { \"filename\" : \"Front.imagestacklayer\" }, { \"filename\" : \"Back.imagestacklayer\" } ] }", to: dir)
    for layer in ["Front", "Back"] {
        let layerDir = dir.appendingPathComponent("\(layer).imagestacklayer")
        try write("{ \(info) }", to: layerDir)
        let content = layerDir.appendingPathComponent("Content.imageset")
        var images: [String] = []
        for scale in scales {
            let name = "\(layer.lowercased())@\(scale)x.png"
            let data = png(width: size.0 * scale, height: size.1 * scale) { r in
                if layer == "Back" { background(r) } else {
                    motif(in: r, height: r.height * 0.86)
                    if dev { devBand(in: r) }
                }
            }
            try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
            try data.write(to: content.appendingPathComponent(name))
            images.append("{ \"filename\" : \"\(name)\", \"idiom\" : \"tv\", \"scale\" : \"\(scale)x\" }")
        }
        try write("{ \"images\" : [ \(images.joined(separator: ", ")) ], \(info) }", to: content)
    }
}

/// A top shelf image: background, motif on the left, the name.
func topShelf(_ dir: URL, size: (Int, Int), dev: Bool) throws {
    var images: [String] = []
    for scale in [1, 2] {
        let name = "top@\(scale)x.png"
        let data = png(width: size.0 * scale, height: size.1 * scale) { r in
            background(r)
            let icon = r.height * 0.6
            motif(in: NSRect(x: r.minX + r.height * 0.25, y: r.minY, width: icon, height: r.height), height: icon)
            let title = NSAttributedString(string: dev ? "Fernsy Dev" : "Fernsy", attributes: [
                .font: NSFont.systemFont(ofSize: r.height * 0.22, weight: .bold), .foregroundColor: NSColor.white,
            ])
            title.draw(at: NSPoint(x: r.minX + r.height * 0.35 + icon, y: r.midY - title.size().height / 2))
            if dev { devBand(in: NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.5)) }
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent(name))
        images.append("{ \"filename\" : \"\(name)\", \"idiom\" : \"tv\", \"scale\" : \"\(scale)x\" }")
    }
    try write("{ \"images\" : [ \(images.joined(separator: ", ")) ], \(info) }", to: dir)
}

try write("{ \(info) }", to: catalog)
for (name, dev) in [("TVAppIcon", false), ("TVAppIcon-Dev", true)] {
    let brand = catalog.appendingPathComponent("\(name).brandassets")
    try? FileManager.default.removeItem(at: brand)
    try write("""
    { "assets" : [
      { "filename" : "App Icon - App Store.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "1280x768" },
      { "filename" : "App Icon.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "400x240" },
      { "filename" : "Top Shelf Image Wide.imageset", "idiom" : "tv", "role" : "top-shelf-image-wide", "size" : "2320x720" },
      { "filename" : "Top Shelf Image.imageset", "idiom" : "tv", "role" : "top-shelf-image", "size" : "1920x720" }
    ], \(info) }
    """, to: brand)
    try imagestack(brand.appendingPathComponent("App Icon - App Store.imagestack"), size: (1280, 768), scales: [1], dev: dev)
    try imagestack(brand.appendingPathComponent("App Icon.imagestack"), size: (400, 240), scales: [1, 2], dev: dev)
    try topShelf(brand.appendingPathComponent("Top Shelf Image Wide.imageset"), size: (2320, 720), dev: dev)
    try topShelf(brand.appendingPathComponent("Top Shelf Image.imageset"), size: (1920, 720), dev: dev)
}
print("✓ Apple TV icons in \(catalog.path)")
