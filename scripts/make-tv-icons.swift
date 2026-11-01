// Renders the Apple TV app's icons into FernsyTV/Assets.xcassets from the Mac icon's design
// (make-icon.swift): layered app icons (back: the Mac icon's indigo background, front: its TV
// alone, so tvOS can tilt them apart) and the top shelf images (drawn from the icon's landscape, tvos-top-shelf
// design 6), as "TVAppIcon" and, with the orange "DEV" band of make-dev-icon.swift,
// "TVAppIcon-Dev". The app icon is a stand-in until the designed Apple TV icon exists.
// Usage: swift scripts/make-tv-icons.swift (again whenever make-icon.swift's design changes)
//        swift scripts/make-tv-icons.swift --top-shelf-variants <folder> (the looks to compare)
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appendingPathComponent("FernsyTV/Assets.xcassets")

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

/// The Mac icon's background (make-icon.swift): the indigo gradient with its soft light at the top.
func background(_ r: NSRect) {
    NSGradient(colors: [rgb(28, 30, 78), rgb(64, 44, 140), rgb(40, 92, 176)])!.draw(in: r, angle: -60)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.14), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2), angle: -90)
}

/// The icon screen's sun and hills (make-icon.swift's `landscape`).
func iconLandscape(in r: NSRect, s: CGFloat) {
    NSGradient(colors: [rgb(255, 196, 120), rgb(242, 118, 96), rgb(120, 62, 140), rgb(48, 36, 104)],
               atLocations: [0, 0.35, 0.72, 1], colorSpace: .sRGB)!.draw(in: r, angle: 90)
    let sun = NSPoint(x: r.midX, y: r.minY + r.height * 0.52)
    let radius = r.width * 0.17
    NSGradient(colors: [rgb(255, 236, 190).withAlphaComponent(0.7), rgb(255, 236, 190).withAlphaComponent(0)])!
        .draw(fromCenter: sun, radius: radius, toCenter: sun, radius: radius * 2.6, options: [])
    rgb(255, 238, 196).setFill()
    NSBezierPath(ovalIn: NSRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2)).fill()
    let layers: [(color: NSColor, base: CGFloat, amplitude: CGFloat, phase: CGFloat)] = [
        (rgb(214, 92, 110), 0.40, 0.07, 0.6), (rgb(150, 58, 120), 0.30, 0.08, 2.1),
        (rgb(92, 40, 112), 0.19, 0.07, 4.0), (rgb(46, 28, 86), 0.08, 0.06, 5.2),
    ]
    for layer in layers {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.minX, y: r.minY))
        var x = r.minX
        while x <= r.maxX + 1 {
            let t = (x - r.minX) / r.width
            let wave = 0.7 * sin(t * 5.2 + layer.phase) + 0.3 * sin(t * 11 + layer.phase * 1.7)
            path.line(to: NSPoint(x: x, y: r.minY + r.height * (layer.base + layer.amplitude * wave)))
            x += max(1, 2 * s)
        }
        path.line(to: NSPoint(x: r.maxX, y: r.minY))
        path.close()
        layer.color.setFill()
        path.fill()
    }
}

/// The icon's TV alone, without the Mac icon's rounded square (that is the back layer here), so
/// tvOS tilts the TV over the background. Drawn from make-icon.swift's 1024 grid: antennas,
/// cabinet, the screen's sunset and the feet, `height` tall and centred.
func motif(in r: NSRect, height: CGFloat) {
    // The TV's box on the 1024 grid: x 196…828, y 196 (feet) … 904 (antenna tips).
    let s = height / 708
    let origin = NSPoint(x: r.midX - 512 * s, y: r.midY - (196 + 354) * s)
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: origin.x + x * s, y: origin.y + y * s) }
    let cream = rgb(246, 242, 255)
    let base = p(512, 712)
    for (dx, dy) in [(-120.0, 150.0), (110.0, 168.0)] {
        let tip = NSPoint(x: base.x + CGFloat(dx) * s, y: base.y + CGFloat(dy) * s)
        let rod = NSBezierPath()
        rod.move(to: base)
        rod.line(to: tip)
        rod.lineWidth = 22 * s
        rod.lineCapStyle = .round
        cream.setStroke()
        rod.stroke()
        rgb(255, 196, 120).setFill()
        NSBezierPath(ovalIn: NSRect(x: tip.x - 24 * s, y: tip.y - 24 * s, width: 48 * s, height: 48 * s)).fill()
    }
    // No drop shadow as on the Mac: tvOS gives the layers their depth itself.
    let cabinet = NSRect(origin: p(196, 236), size: NSSize(width: 632 * s, height: 492 * s))
    cream.setFill()
    NSBezierPath(roundedRect: cabinet, xRadius: 110 * s, yRadius: 110 * s).fill()
    let screen = cabinet.insetBy(dx: 44 * s, dy: 44 * s)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screen, xRadius: 74 * s, yRadius: 74 * s).addClip()
    iconLandscape(in: screen, s: s)
    NSGraphicsContext.restoreGraphicsState()
    cream.setFill()
    for x in [300.0, 668.0] {
        NSBezierPath(roundedRect: NSRect(origin: p(CGFloat(x), 196), size: NSSize(width: 56 * s, height: 60 * s)),
                     xRadius: 16 * s, yRadius: 16 * s).fill()
    }
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
                    motif(in: r, height: r.height * 0.74)
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

// MARK: Top Shelf image (tvos-top-shelf design 6)

/// The static Top Shelf image, shown without content: the icon's sunset landscape across the
/// full width, the sun at the golden ratio, a few stars, and a small TV with the name at the left.
/// Three looks to choose from; `shelfVariant` is the one the asset catalog gets.
enum ShelfVariant: String, CaseIterable {
    /// The icon's evening: the sun resting on the hills, warm sky.
    case sunset
    /// Later: the sun half set behind the hills, a deeper sky with more stars.
    case dusk
    /// The sun high at the golden point of both axes, a lighter sky, few stars.
    case twilight

    var sky: [NSColor] {
        switch self {
        case .sunset: [rgb(255, 196, 120), rgb(242, 118, 96), rgb(120, 62, 140), rgb(48, 36, 104)]
        case .dusk: [rgb(250, 150, 100), rgb(196, 84, 112), rgb(82, 44, 124), rgb(26, 22, 70)]
        case .twilight: [rgb(255, 214, 150), rgb(246, 140, 110), rgb(150, 80, 150), rgb(60, 46, 122)]
        }
    }
    var skyLocations: [CGFloat] { self == .dusk ? [0, 0.22, 0.6, 1] : [0, 0.3, 0.68, 1] }
    /// The sun's centre and radius, as shares of the height.
    var sun: (y: CGFloat, radius: CGFloat) {
        switch self {
        case .sunset: (0.36, 0.17)
        case .dusk: (0.24, 0.2)
        case .twilight: (0.618, 0.1)
        }
    }
    var stars: Int { self == .dusk ? 34 : self == .sunset ? 18 : 10 }
    /// The sun's centre across, as a share of the width: right of the centred name.
    var sunX: CGFloat { self == .sunset ? 0.75 : 0.618 }
}

/// The TV and "Fernsy" centred across, in the upper sky: tvOS crops the sides of the top shelf
/// image depending on the TV, so nothing important may sit near the edges.
struct ShelfTitle {
    let tv: NSRect
    let title: NSAttributedString
    let titleOrigin: NSPoint
    var frame: NSRect { tv.union(NSRect(origin: titleOrigin, size: title.size())) }

    init(in r: NSRect) {
        let tvHeight = r.height * 0.17
        let font = NSFont.systemFont(ofSize: r.height * 0.1, weight: .bold)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: font.pointSize) } ?? font
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = r.height * 0.012
        shadow.shadowOffset = NSSize(width: 0, height: -r.height * 0.004)
        title = NSAttributedString(string: "Fernsy", attributes: [.font: rounded, .foregroundColor: rgb(246, 242, 255), .shadow: shadow])
        let tvWidth = tvHeight * 632 / 600, gap = r.height * 0.045
        let total = tvWidth + gap + title.size().width
        tv = NSRect(x: r.midX - total / 2, y: r.minY + r.height * 0.55, width: tvWidth, height: tvHeight)
        titleOrigin = NSPoint(x: tv.maxX + gap, y: tv.minY + tv.height * 0.42 - title.size().height / 2)
    }
}

let shelfVariant = ShelfVariant.sunset

/// Sky, sun with its glow, stars and four layers of hills, as in the icon's screen (make-icon.swift).
func shelfLandscape(in r: NSRect, _ variant: ShelfVariant) {
    let h = r.height
    NSGradient(colors: variant.sky, atLocations: variant.skyLocations, colorSpace: .sRGB)!.draw(in: r, angle: 90)
    // Stars in the upper sky, from a fixed sequence so every run draws the same ones.
    var seed: UInt64 = 0x5EED_F00D
    func random() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
    }
    let sun = NSPoint(x: r.minX + r.width * variant.sunX, y: r.minY + h * variant.sun.y)
    let radius = h * variant.sun.radius
    for _ in 0..<variant.stars {
        let point = NSPoint(x: r.minX + random() * r.width, y: r.minY + h * (0.62 + 0.36 * random()))
        let size = h * (0.004 + 0.005 * random())
        // None in the sun's glow or next to the TV and the name.
        let nearTitle = ShelfTitle(in: r).frame.insetBy(dx: -h * 0.06, dy: -h * 0.06).contains(point)
        guard hypot(point.x - sun.x, point.y - sun.y) > radius * 2.4, !nearTitle else { continue }
        NSColor.white.withAlphaComponent(0.45 + 0.45 * random()).setFill()
        NSBezierPath(ovalIn: NSRect(x: point.x - size, y: point.y - size, width: size * 2, height: size * 2)).fill()
    }
    NSGradient(colors: [rgb(255, 236, 190).withAlphaComponent(0.7), rgb(255, 236, 190).withAlphaComponent(0)])!
        .draw(fromCenter: sun, radius: radius, toCenter: sun, radius: radius * 2.8, options: [])
    rgb(255, 238, 196).setFill()
    NSBezierPath(ovalIn: NSRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2)).fill()
    // The waves follow the height, so the wide image has more hills, not wider ones.
    let layers: [(color: NSColor, base: CGFloat, amplitude: CGFloat, phase: CGFloat)] = [
        (rgb(214, 92, 110), 0.31, 0.05, 0.6), (rgb(150, 58, 120), 0.23, 0.06, 2.1),
        (rgb(92, 40, 112), 0.14, 0.05, 4.0), (rgb(46, 28, 86), 0.06, 0.04, 5.2),
    ]
    for layer in layers {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r.minX, y: r.minY))
        var x = r.minX
        while x <= r.maxX + 1 {
            let t = (x - r.minX) / h
            let wave = 0.7 * sin(t * 2.6 + layer.phase) + 0.3 * sin(t * 5.5 + layer.phase * 1.7)
            path.line(to: NSPoint(x: x, y: r.minY + h * (layer.base + layer.amplitude * wave)))
            x += 2
        }
        path.line(to: NSPoint(x: r.maxX, y: r.minY))
        path.close()
        layer.color.setFill()
        path.fill()
    }
}

/// The icon's TV as an outline (cabinet, antennas with their tips, feet), `height` tall.
func shelfTV(in r: NSRect) {
    let s = r.height / 600   // the icon's TV is about 600 px tall on its 1024 canvas
    let cream = rgb(246, 242, 255)
    let cabinet = NSRect(x: r.minX, y: r.minY + 40 * s, width: 632 * s, height: 492 * s)
    let outline = NSBezierPath(roundedRect: cabinet.insetBy(dx: 22 * s, dy: 22 * s), xRadius: 92 * s, yRadius: 92 * s)
    outline.lineWidth = 44 * s
    cream.setStroke()
    outline.stroke()
    let base = NSPoint(x: cabinet.midX, y: cabinet.maxY)
    for (dx, dy) in [(-120.0, 150.0), (110.0, 168.0)] {
        let tip = NSPoint(x: base.x + CGFloat(dx) * s * 0.8, y: base.y + CGFloat(dy) * s * 0.4)
        let rod = NSBezierPath()
        rod.move(to: base)
        rod.line(to: tip)
        rod.lineWidth = 26 * s
        rod.lineCapStyle = .round
        rod.stroke()
        rgb(255, 196, 120).setFill()
        NSBezierPath(ovalIn: NSRect(x: tip.x - 30 * s, y: tip.y - 30 * s, width: 60 * s, height: 60 * s)).fill()
    }
    cream.setFill()
    for x in [104.0, 472.0] {
        NSBezierPath(roundedRect: NSRect(x: cabinet.minX + CGFloat(x) * s, y: r.minY, width: 56 * s, height: 60 * s),
                     xRadius: 16 * s, yRadius: 16 * s).fill()
    }
}

/// The whole image: landscape, then the TV and "Fernsy" centred in the sky.
func shelfImage(in r: NSRect, _ variant: ShelfVariant, dev: Bool) {
    shelfLandscape(in: r, variant)
    let lockup = ShelfTitle(in: r)
    shelfTV(in: lockup.tv)
    lockup.title.draw(at: lockup.titleOrigin)
    if dev { devBand(in: NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.5)) }
}

/// A top shelf image in the asset catalog, @1x and @2x.
func topShelf(_ dir: URL, size: (Int, Int), dev: Bool) throws {
    var images: [String] = []
    for scale in [1, 2] {
        let name = "top@\(scale)x.png"
        let data = png(width: size.0 * scale, height: size.1 * scale) { r in shelfImage(in: r, shelfVariant, dev: dev) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: dir.appendingPathComponent(name))
        images.append("{ \"filename\" : \"\(name)\", \"idiom\" : \"tv\", \"scale\" : \"\(scale)x\" }")
    }
    try write("{ \"images\" : [ \(images.joined(separator: ", ")) ], \(info) }", to: dir)
}

// --top-shelf-variants <folder>: every variant as PNG files to compare (normal and wide, release
// and dev, @1x), and nothing in the asset catalog.
if let flag = CommandLine.arguments.firstIndex(of: "--top-shelf-variants") {
    guard CommandLine.arguments.count > flag + 1 else { fatalError("usage: --top-shelf-variants <folder>") }
    let folder = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for variant in ShelfVariant.allCases {
        for (suffix, width) in [("", 1920), ("-wide", 2320)] {
            for dev in [false, true] {
                let data = png(width: width, height: 720) { r in shelfImage(in: r, variant, dev: dev) }
                try data.write(to: folder.appendingPathComponent("\(variant.rawValue)\(suffix)\(dev ? "-dev" : "").png"))
            }
        }
    }
    print("✓ Top Shelf variants in \(folder.path)")
    exit(0)
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
