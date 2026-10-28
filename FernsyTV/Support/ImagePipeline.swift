import CryptoKit
import FernsyCore
import ImageIO
import SwiftUI
import UIKit

/// Posters, backdrops and logos (design E of tvos-library): downsampled to the size they are
/// shown at, kept in memory and in Caches/Images, so grids do not reload while scrolling.
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    /// Loads in flight by key: Start shows the same poster in several rows at once, and each
    /// would otherwise download it.
    private var running: [String: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()

    private init() {
        memory.countLimit = 600
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Images", isDirectory: true)
        #if DEBUG
        // IPTV_FRESHIMAGES=1: start without the images of earlier runs (counting loads in tests).
        if ProcessInfo.processInfo.environment["IPTV_FRESHIMAGES"] == "1" { try? FileManager.default.removeItem(at: folder) }
        #endif
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func key(_ url: URL, _ maxPixel: Int) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(digest.prefix(32))-\(maxPixel)"
    }

    func cached(_ url: URL, maxPixel: Int) -> UIImage? {
        memory.object(forKey: key(url, maxPixel) as NSString)
    }

    func image(_ url: URL, maxPixel: Int) async -> UIImage? {
        let name = key(url, maxPixel)
        if let image = memory.object(forKey: name as NSString) { return image }
        let task: Task<UIImage?, Never> = lock.withLock {
            if let task = running[name] { return task }
            let task = load(url, maxPixel: maxPixel, name: name)
            running[name] = task
            return task
        }
        let image = await task.value
        lock.withLock { running[name] = nil }
        return image
    }

    private func load(_ url: URL, maxPixel: Int, name: String) -> Task<UIImage?, Never> {
        let file = folder.appendingPathComponent(name)
        let memory = memory
        return Task.detached(priority: .utility) { () -> UIImage? in
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
                memory.setObject(image, forKey: name as NSString)
                return image
            }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  let image = Self.downsample(data, maxPixel: maxPixel) else { return nil }
            if let jpeg = image.jpegData(compressionQuality: 0.85) { try? jpeg.write(to: file, options: .atomic) }
            AppLog.detail(.app, "image loaded: \(url.lastPathComponent) at \(maxPixel) px")
            memory.setObject(image, forKey: name as NSString)
            return image
        }
    }

    private static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// An image from the pipeline, filling its frame; `placeholder` until it is there (or fails).
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var maxPixel = 600
    @ViewBuilder let placeholder: Placeholder
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            image = ImagePipeline.shared.cached(url, maxPixel: maxPixel)
            if image == nil { image = await ImagePipeline.shared.image(url, maxPixel: maxPixel) }
        }
    }
}

/// A stable colour gradient for items without artwork (like the design's placeholders).
struct ArtPlaceholder: View {
    let seed: String

    var body: some View {
        // A fixed checksum: hashValue changes with every launch.
        let sum = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let hue = Double(sum % 360) / 360
        LinearGradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 0.62), Color(hue: hue, saturation: 0.5, brightness: 0.2)],
                       startPoint: .top, endPoint: .bottom)
    }
}
