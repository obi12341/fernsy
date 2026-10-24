import AppKit
import ImageIO
import SwiftUI

/// Fetches, downsamples and caches remote artwork. Thumbnails are decoded off the
/// main thread at the size they are displayed, which keeps large grids smooth.
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let cache = NSCache<NSString, NSImage>()
    private let tones = NSCache<NSString, ToneBox>()
    private let session: URLSession

    private init() {
        cache.countLimit = 1500
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 512 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL, maxPixel: Int) -> NSImage? {
        cache.object(forKey: "\(maxPixel)|\(url.absoluteString)" as NSString)
    }

    func image(_ url: URL, maxPixel: Int) async -> NSImage? {
        let key = "\(maxPixel)|\(url.absoluteString)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        let (image, tone) = await Task.detached(priority: .utility) { () -> (NSImage?, LogoTone?) in
            let image = Self.downsample(data, maxPixel: maxPixel)
            return (image, image.flatMap { Self.measureTone($0) })
        }.value
        if let image { cache.setObject(image, forKey: key) }
        if let tone { tones.setObject(ToneBox(tone), forKey: url.absoluteString as NSString) }
        return image
    }

    /// How a loaded logo looks, measured once when it was decoded.
    func tone(for url: URL) -> LogoTone? {
        tones.object(forKey: url.absoluteString as NSString)?.tone
    }

    /// Dark on a transparent background (needs a light tile) or anything else, from a 16×16
    /// thumbnail: share of transparent pixels and mean luminance of the opaque ones.
    static func measureTone(_ image: NSImage) -> LogoTone? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var transparent = 0, opaque = 0
        var luminance = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Double(pixels[i + 3]) / 255
            if a < 0.5 { transparent += 1; continue }
            opaque += 1
            // Un-premultiply, then Rec. 709 luma.
            let r = Double(pixels[i]) / 255 / a, g = Double(pixels[i + 1]) / 255 / a, b = Double(pixels[i + 2]) / 255 / a
            luminance += 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        guard opaque > 0 else { return .other }
        let clear = Double(transparent) / Double(side * side)
        return clear > 0.2 && luminance / Double(opaque) < 0.35 ? .darkOnClear : .other
    }

    private static func downsample(_ data: Data, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

enum LogoTone: Sendable {
    /// Dark artwork on a transparent background: invisible on the graphite tile.
    case darkOnClear
    case other
}

private final class ToneBox {
    let tone: LogoTone
    init(_ tone: LogoTone) { self.tone = tone }
}

struct RemoteImage<Placeholder: View>: View {
    let url: String?
    var maxPixel: Int = 400
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url, let parsed = URL(string: url) else {
                image = nil
                return
            }
            if let hit = ImagePipeline.shared.cached(parsed, maxPixel: maxPixel) {
                image = hit
                return
            }
            image = nil
            image = await ImagePipeline.shared.image(parsed, maxPixel: maxPixel)
        }
    }
}
