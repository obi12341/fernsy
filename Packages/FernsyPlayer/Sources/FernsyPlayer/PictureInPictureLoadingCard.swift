import AVFoundation
import CoreImage
import CoreText
import CoreVideo
import FernsyCore
import Foundation

/// Animated loading picture for the PiP window. The PiP window mirrors only the display layer's
/// video frames (no sublayers, no system spinner for sample-buffer sources), so while a new item
/// loads the card renders frames itself – the last picture darkened, a rotating spinner and the
/// title – and enqueues them into the layer's video renderer (through the engine's video sink). The frames keep the size of the
/// last picture: a change of the frame size makes the system misplace its PiP mirror (see
/// `PictureInPictureStage.refit()`). The card runs on its own queue and is stopped synchronously
/// right before the playback session sends its first frame, so the renderer never gets frames
/// from both.
public final class PictureInPictureLoadingCard: @unchecked Sendable {
    private static let fps = 10

    private let sink: VideoSink
    private let queue = DispatchQueue(label: "pip.loading-card", qos: .userInitiated)
    private let imageContext = CIContext()
    // queue only:
    private var timer: DispatchSourceTimer?
    private var title = ""
    /// The target channel's logo (or its initials) on a tile left of the title.
    private var logo: CGImage?
    private var initials = ""
    private var lightTile = false
    private var frame = 0
    private var background: CVPixelBuffer?
    private var pool: CVPixelBufferPool?
    private var format: CMVideoFormatDescription?

    public init(sink: VideoSink) {
        self.sink = sink
    }

    /// `last` is the picture shown now; the card is drawn on it, darkened, at its size.
    public func start(title: String, over last: CVPixelBuffer?, logo: CGImage? = nil, initials: String = "", lightTile: Bool = false) {
        queue.sync {
            stopOnQueue()
            self.title = title
            self.logo = logo
            self.initials = initials
            self.lightTile = lightTile
            frame = 0
            prepare(from: last)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 1 / Double(Self.fps))
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
            AppLog.detail(.pip, "loading picture for \(title), \(background.map { "\(CVPixelBufferGetWidth($0))×\(CVPixelBufferGetHeight($0))" } ?? "-")")
        }
    }

    public func stop() {
        queue.sync { stopOnQueue() }
    }

    private func stopOnQueue() {
        guard let timer else { return }
        timer.cancel()
        self.timer = nil
        AppLog.detail(.pip, "loading picture stopped after \(frame) frames")
    }

    /// The last picture, blurred and darkened, as BGRA at its own size (1280×720 black when there is none).
    private func prepare(from last: CVPixelBuffer?) {
        let width = last.map(CVPixelBufferGetWidth) ?? 1280
        let height = last.map(CVPixelBufferGetHeight) ?? 720
        if let background, CVPixelBufferGetWidth(background) == width, CVPixelBufferGetHeight(background) == height {
            // Same size as before: the pool and format stay.
        } else {
            let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                                               kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
                                               kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            pool = nil
            format = nil
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        }
        var buffer: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return }
        let image = last.map {
            let picture = CIImage(cvPixelBuffer: $0)
            return picture.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: Double(height) / 90])
                .cropped(to: picture.extent)
        }
            ?? CIImage(color: CIColor(red: 0.06, green: 0.06, blue: 0.06)).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        imageContext.render(image, to: buffer)
        background = buffer
    }

    private func tick() {
        guard timer != nil, let sample = render() else { return }
        // Ten frames a second for a still picture: the queue never fills up.
        _ = sink.enqueue(sample)
        frame += 1
    }

    private func render() -> CMSampleBuffer? {
        var buffer: CVPixelBuffer?
        guard let background, let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        CVPixelBufferLockBaseAddress(background, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(background, .readOnly)
            CVPixelBufferUnlockBaseAddress(buffer, [])
        }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard let target = CVPixelBufferGetBaseAddress(buffer), let source = CVPixelBufferGetBaseAddress(background),
              CVPixelBufferGetBytesPerRow(background) == rowBytes else { return nil }
        memcpy(target, source, rowBytes * height)
        guard let context = CGContext(data: target, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        draw(in: context, width: CGFloat(width), height: CGFloat(height))

        if format == nil { CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format) }
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(Self.fps)),
                                        presentationTimeStamp: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(Self.fps)),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        guard let sample, let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else { return nil }
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        return sample
    }

    private func draw(in context: CGContext, width: CGFloat, height: CGFloat) {
        let unit = height / 720 // sizes below are for a 720-line picture
        context.setFillColor(CGColor(gray: 0, alpha: 0.72))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Spinner: 12 spokes, the bright one moving clockwise once per 1.2 s.
        let center = CGPoint(x: width / 2, y: height * 0.56)
        let spokes = 12
        context.setLineWidth(9 * unit)
        context.setLineCap(.round)
        for i in 0..<spokes {
            let angle = CGFloat.pi / 2 - CGFloat(i) * 2 * .pi / CGFloat(spokes)
            let age = ((frame - i) % spokes + spokes) % spokes
            context.setStrokeColor(CGColor(gray: 1, alpha: max(0.15, 1 - CGFloat(age) / CGFloat(spokes))))
            context.move(to: CGPoint(x: center.x + cos(angle) * 26 * unit, y: center.y + sin(angle) * 26 * unit))
            context.addLine(to: CGPoint(x: center.x + cos(angle) * 50 * unit, y: center.y + sin(angle) * 50 * unit))
            context.strokePath()
        }

        // Title below the spinner, one line, shortened with "…" when too wide.
        let font = CTFontCreateWithName("SF Pro Display Semibold" as CFString, 46 * unit, nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(gray: 1, alpha: 0.9)]
        let full = CTLineCreateWithAttributedString(NSAttributedString(string: title, attributes: attributes))
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        // A logo tile (13:8) left of the title, when the target is a channel.
        let hasTile = logo != nil || !initials.isEmpty
        let tile = CGSize(width: 104 * unit, height: 64 * unit)
        let gap = hasTile ? 22 * unit : 0
        let line = CTLineCreateTruncatedLine(full, Double(width * 0.85 - (hasTile ? tile.width + gap : 0)), .end, ellipsis) ?? full
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let total = (hasTile ? tile.width + gap : 0) + lineWidth
        let left = (width - total) / 2
        let baseline = height * 0.32
        if hasTile {
            let rect = CGRect(x: left, y: baseline - tile.height * 0.3, width: tile.width, height: tile.height)
            context.setFillColor(lightTile ? CGColor(srgbRed: 0.91, green: 0.91, blue: 0.93, alpha: 1)
                                           : CGColor(srgbRed: 0.17, green: 0.17, blue: 0.2, alpha: 1))
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 12 * unit, cornerHeight: 12 * unit, transform: nil))
            context.fillPath()
            if let logo {
                let inset = rect.insetBy(dx: tile.width * 0.12, dy: tile.width * 0.12)
                let scale = min(inset.width / CGFloat(logo.width), inset.height / CGFloat(logo.height))
                let size = CGSize(width: CGFloat(logo.width) * scale, height: CGFloat(logo.height) * scale)
                context.draw(logo, in: CGRect(x: inset.midX - size.width / 2, y: inset.midY - size.height / 2, width: size.width, height: size.height))
            } else {
                let small = CTFontCreateWithName("SF Pro Display Heavy" as CFString, 26 * unit, nil)
                let mark = CTLineCreateWithAttributedString(NSAttributedString(string: initials,
                    attributes: [.font: small, .foregroundColor: CGColor(gray: 1, alpha: 0.8)]))
                let markWidth = CGFloat(CTLineGetTypographicBounds(mark, nil, nil, nil))
                context.textPosition = CGPoint(x: rect.midX - markWidth / 2, y: rect.midY - 9 * unit)
                CTLineDraw(mark, context)
            }
        }
        context.textPosition = CGPoint(x: left + (hasTile ? tile.width + gap : 0), y: baseline)
        CTLineDraw(line, context)
    }
}
