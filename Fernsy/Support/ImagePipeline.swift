import AppKit
import ImageIO
import SwiftUI

/// Fetches, downsamples and caches remote artwork. Thumbnails are decoded off the
/// main thread at the size they are displayed, which keeps large grids smooth.
final class ImagePipeline {
    static let shared = ImagePipeline()

    private let cache = NSCache<NSString, NSImage>()
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
        let image = await Task.detached(priority: .utility) { Self.downsample(data, maxPixel: maxPixel) }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
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
