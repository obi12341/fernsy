// Renders the app icon into Fernsy/Assets.xcassets/AppIcon.appiconset.
// Usage: swift scripts/make-icon.swift
//
// Motif: a friendly retro TV with antennas showing a sunset landscape – the same sun and
// layered hills used for Fernsy's store artwork – on an indigo background.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("Fernsy/Assets.xcassets/AppIcon.appiconset")

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

/// Sun and layered hills filling `r`.
func landscape(in r: NSRect, s: CGFloat) {
    NSGradient(colors: [rgb(255, 196, 120), rgb(242, 118, 96), rgb(120, 62, 140), rgb(48, 36, 104)],
               atLocations: [0, 0.35, 0.72, 1], colorSpace: .sRGB)!.draw(in: r, angle: 90)
    let sun = NSPoint(x: r.midX, y: r.minY + r.height * 0.52)
    let radius = r.width * 0.17
    NSGradient(colors: [rgb(255, 236, 190, 0.7), rgb(255, 236, 190, 0)])!
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

func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let cream = rgb(246, 242, 255)

    // macOS icon grid: 824×824 body centred on a 1024 canvas, continuous corners.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [rgb(28, 30, 78), rgb(64, 44, 140), rgb(40, 92, 176)])!.draw(in: body, angle: -60)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.14), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Antennas
    let base = NSPoint(x: 512 * s, y: 712 * s)
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

    // Cabinet
    let cabinet = NSRect(x: 196 * s, y: 236 * s, width: 632 * s, height: 492 * s)
    NSGraphicsContext.saveGraphicsState()
    let cabinetShadow = NSShadow()
    cabinetShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    cabinetShadow.shadowBlurRadius = 30 * s
    cabinetShadow.shadowOffset = NSSize(width: 0, height: -14 * s)
    cabinetShadow.set()
    cream.setFill()
    NSBezierPath(roundedRect: cabinet, xRadius: 110 * s, yRadius: 110 * s).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Screen
    let screen = cabinet.insetBy(dx: 44 * s, dy: 44 * s)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screen, xRadius: 74 * s, yRadius: 74 * s).addClip()
    landscape(in: screen, s: s)
    NSGraphicsContext.restoreGraphicsState()

    // Feet
    cream.setFill()
    for x in [300.0, 668.0] {
        NSBezierPath(roundedRect: NSRect(x: CGFloat(x) * s, y: 196 * s, width: 56 * s, height: 60 * s),
                     xRadius: 16 * s, yRadius: 16 * s).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in sizes {
    let px = points * scale
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let data = renderIcon(size: CGFloat(px)).representation(using: .png, properties: [:])!
    try! data.write(to: output.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon images to \(output.path)")
