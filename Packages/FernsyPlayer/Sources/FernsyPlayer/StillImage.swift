import CoreImage
import CoreText
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

/// Stills for the assistant (MCP `snapshot` and `frames`): decoded pictures to CGImage, a
/// labelled contact sheet, JPEG through ImageIO (the bundled FFmpeg has no encoders).
public enum StillImage {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The picture scaled to at most `maxWidth` pixels, wider pixels (anamorphic video) included.
    public static func image(from pixelBuffer: CVPixelBuffer, maxWidth: CGFloat, pixelAspect: CGFloat = 1) -> CGImage? {
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let width = image.extent.width * max(pixelAspect, 0.1)
        let scale = min(1, maxWidth / max(width, 1))
        image = image.transformed(by: CGAffineTransform(scaleX: scale * max(pixelAspect, 0.1), y: scale))
        return context.createCGImage(image, from: image.extent.integral, format: .RGBA8,
                                     colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    public static func jpeg(_ image: CGImage, quality: Double = 0.75) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Tiles in rows of `columns`, each with its label in a dark box in the lower left corner.
    public static func contactSheet(_ tiles: [(image: CGImage, label: String)], tileWidth: CGFloat = 320, columns: Int = 6) -> CGImage? {
        guard let first = tiles.first?.image else { return nil }
        let tileHeight = (tileWidth * CGFloat(first.height) / CGFloat(max(first.width, 1))).rounded()
        let gap: CGFloat = 4
        let cols = min(columns, tiles.count)
        let rows = (tiles.count + cols - 1) / cols
        let width = CGFloat(cols) * tileWidth + CGFloat(cols + 1) * gap
        let height = CGFloat(rows) * tileHeight + CGFloat(rows + 1) * gap
        guard let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(gray: 0.1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, 15, nil)
        for (index, tile) in tiles.enumerated() {
            let col = index % cols, row = index / cols
            // Core Graphics counts from the bottom; the first row goes on top.
            let rect = CGRect(x: gap + CGFloat(col) * (tileWidth + gap),
                              y: height - CGFloat(row + 1) * (tileHeight + gap),
                              width: tileWidth, height: tileHeight)
            ctx.draw(tile.image, in: rect)
            let text = NSAttributedString(string: tile.label, attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1),
            ])
            let line = CTLineCreateWithAttributedString(text)
            let bounds = CTLineGetImageBounds(line, ctx)
            let box = CGRect(x: rect.minX, y: rect.minY, width: bounds.width + 10, height: 22)
            ctx.setFillColor(gray: 0, alpha: 0.7)
            ctx.fill(box)
            ctx.textPosition = CGPoint(x: box.minX + 5, y: box.minY + 6)
            CTLineDraw(line, ctx)
        }
        return ctx.makeImage()
    }
}
