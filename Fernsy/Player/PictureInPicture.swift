import AVKit
import Combine
import CoreImage
import CoreText

/// System Picture in Picture for the player's display layer (every source renders into it).
/// The player screen hides its window while PiP runs and reacts to "back" and "close".
@MainActor
final class PictureInPicture: NSObject, ObservableObject {
    @Published private(set) var isPossible = false
    @Published private(set) var isActive = false

    /// PiP is about to start: prepare the layer for the PiP window.
    var onWillStart: () -> Void = {}
    /// PiP started: the player window can go.
    var onStarted: () -> Void = {}
    /// "Back" in the PiP window: show the player window again.
    var onRestore: () -> Void = {}
    /// The PiP window was closed: stop playback like closing the player window.
    var onClosed: () -> Void = {}

    private let engine: PlayerEngine
    private var controller: AVPictureInPictureController?
    private var restoring = false
    private var observers: Set<AnyCancellable> = []

    init(engine: PlayerEngine) {
        self.engine = engine
        super.init()
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: engine.displayLayer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        self.controller = controller
        controller.publisher(for: \.isPictureInPicturePossible).receive(on: RunLoop.main)
            .sink { [weak self] in self?.isPossible = $0 }.store(in: &observers)
        // The PiP window shows pause state, duration and live; keep it current.
        engine.$isPaused.removeDuplicates().sink { [weak self] _ in self?.controller?.invalidatePlaybackState() }.store(in: &observers)
        engine.$media.sink { [weak self] _ in self?.controller?.invalidatePlaybackState() }.store(in: &observers)
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else if canStart {
            controller.startPictureInPicture()
        }
    }

    /// The system reports PiP as possible before the layer shows a picture, but starting then
    /// crashes inside AVKit (the PiP window lays out a size from the missing picture).
    var canStart: Bool {
        isPossible && engine.lastPicture.value != nil
    }

    /// Ends PiP by returning to the player window (debug hook and window reopening).
    func restore() {
        guard let controller, controller.isPictureInPictureActive else { return }
        restoring = true
        controller.stopPictureInPicture()
    }
}

/// Works around macOS mirroring a sample-buffer PiP source 1:1 instead of scaling it to the PiP
/// window (seen on macOS 26.4 and 27.0, FB22411168): the PiP window then shows only the
/// bottom-left part of the picture. While PiP runs, the display layer moves into an invisible
/// window of its own that follows the PiP window's size, so the mirrored layer is exactly as large
/// as the PiP window, and a stale overlay covering the top of the picture is hidden. The SwiftUI
/// player window keeps its size (resizing it made SwiftUI shrink it to nothing on the way back).
@MainActor
final class PictureInPictureStage {
    private weak var surface: VideoSurfaceView?
    private var layer: AVSampleBufferDisplayLayer?
    private var stage: NSWindow?
    private var windowsBefore: Set<ObjectIdentifier> = []
    private var observer: NSObjectProtocol?

    /// PiP is about to start: move the layer from `surface` into the invisible stage window,
    /// placed where the video is now.
    func prepare(surface: VideoSurfaceView) {
        guard stage == nil, let layer = surface.displayLayer, let window = surface.window else { return }
        windowsBefore = Set(NSApp.windows.map(ObjectIdentifier.init))
        let stage = NSWindow(contentRect: window.convertToScreen(surface.convert(surface.bounds, to: nil)),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        stage.isReleasedWhenClosed = false
        stage.alphaValue = 0
        stage.ignoresMouseEvents = true
        stage.isExcludedFromWindowsMenu = true
        stage.collectionBehavior = [.transient, .ignoresCycle]
        let content = NSView()
        content.wantsLayer = true
        stage.contentView = content
        stage.orderFront(nil)
        surface.displayLayer = nil
        place(layer, in: content)
        self.surface = surface
        self.layer = layer
        self.stage = stage
    }

    /// PiP started: follow the PiP window's size from now on.
    func begin() {
        guard let stage,
              let panel = NSApp.windows.first(where: { !windowsBefore.contains(ObjectIdentifier($0)) && $0 !== stage }),
              let content = panel.contentView else {
            AppLog.warning(.pip, "PiP window not found, picture stays at the player's size")
            return
        }
        AppLog.detail(.pip, "PiP window at \(panel.frame)")
        fit(to: content.bounds.size)
        // The system builds the PiP window's views right after the start.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.hideStaleOverlay(in: content) }
        content.postsFrameChangedNotifications = true
        observer = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: content, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fit(to: content.bounds.size)
                self?.hideStaleOverlay(in: content)
            }
        }
    }

    /// PiP ended: the layer goes back into the player.
    func end() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.removeFromSuperlayer()
            surface?.displayLayer = layer
            CATransaction.commit()
            // Back in the player window the layer stays black until its queue is flushed;
            // the session refills it right away.
            layer.flush()
        }
        stage?.orderOut(nil)
        stage = nil
        layer = nil
        surface = nil
    }

    private func fit(to size: NSSize) {
        guard let stage, let content = stage.contentView, let layer, size.width > 0, size.height > 0 else { return }
        stage.setFrame(NSRect(x: stage.frame.minX, y: stage.frame.maxY - size.height, width: size.width, height: size.height), display: false)
        place(layer, in: content)
        AppLog.detail(.pip, "video sized to the PiP window: \(Int(size.width))×\(Int(size.height))")
    }

    /// Second part of the same system bug: an empty black view inside the PiP window keeps the
    /// size of the original layer and covers the top of the picture (about 21 pt at the default
    /// PiP size). It can only be found by its class name; if a later macOS renames or drops it,
    /// nothing is hidden and the picture is merely covered as before.
    /// A change of the frame size (another item, the loading picture) makes the system lay out its
    /// mirror anew, and it comes out shifted and cropped again. Changing the layer's frame and
    /// setting it back afterwards brings it in line; done twice, since the new size only counts
    /// once a frame of it is on screen.
    func refit() {
        for delay in [0.25, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let stage = self.stage, let content = stage.contentView, let layer = self.layer else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.frame = content.bounds.insetBy(dx: 1, dy: 1)
                CATransaction.commit()
                DispatchQueue.main.async {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    layer.frame = content.bounds
                    CATransaction.commit()
                }
            }
        }
    }

    private func hideStaleOverlay(in view: NSView) {
        if String(describing: type(of: view)) == "AVPictureInPictureCALayerHostView" {
            if !view.isHidden {
                view.isHidden = true
                AppLog.detail(.pip, "hid the stale overlay in the PiP window")
            }
            return
        }
        view.subviews.forEach(hideStaleOverlay)
    }

    private func place(_ layer: CALayer, in content: NSView) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if layer.superlayer !== content.layer { content.layer?.addSublayer(layer) }
        layer.frame = content.bounds
        CATransaction.commit()
    }
}

/// Animated loading picture for the PiP window. The PiP window mirrors only the display layer's
/// video frames (no sublayers, no system spinner for sample-buffer sources), so while a new item
/// loads the card renders frames itself – the last picture darkened, a rotating spinner and the
/// title – and enqueues them into the layer's video renderer. The frames keep the size of the
/// last picture: a change of the frame size makes the system misplace its PiP mirror (see
/// `PictureInPictureStage.refit()`). The card runs on its own queue and is stopped synchronously
/// right before the playback session sends its first frame, so the renderer never gets frames
/// from both.
final class PictureInPictureLoadingCard: @unchecked Sendable {
    private static let fps = 10

    private let renderer: AVSampleBufferVideoRenderer
    private let queue = DispatchQueue(label: "pip.loading-card", qos: .userInitiated)
    private let imageContext = CIContext()
    // queue only:
    private var timer: DispatchSourceTimer?
    private var title = ""
    private var frame = 0
    private var background: CVPixelBuffer?
    private var pool: CVPixelBufferPool?
    private var format: CMVideoFormatDescription?

    init(renderer: AVSampleBufferVideoRenderer) {
        self.renderer = renderer
    }

    /// `last` is the picture shown now; the card is drawn on it, darkened, at its size.
    func start(title: String, over last: CVPixelBuffer?) {
        queue.sync {
            stopOnQueue()
            self.title = title
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

    func stop() {
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
        if renderer.isReadyForMoreMediaData { renderer.enqueue(sample) }
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
        let line = CTLineCreateTruncatedLine(full, Double(width * 0.85), .end, ellipsis) ?? full
        let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
        context.textPosition = CGPoint(x: (width - CGFloat(lineWidth)) / 2, y: height * 0.32)
        CTLineDraw(line, context)
    }
}

extension PictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        MainActor.assumeIsolated { engine.setPaused(!playing) }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        MainActor.assumeIsolated {
            if engine.isLiveStream || engine.isTimeshift {
                return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
            }
            let duration = engine.progress.duration
            guard duration > 0 else { return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity) }
            // On the layer's clock: the item's start is the clock now minus the item position.
            let start = engine.clockTime - engine.progress.position
            return CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: duration, preferredTimescale: 600))
        }
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        MainActor.assumeIsolated { engine.isPaused }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        MainActor.assumeIsolated { engine.seek(by: skipInterval.seconds) }
        completionHandler()
    }
}

extension PictureInPicture: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated { onWillStart() }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isActive = true
            AppLog.info(.pip, "started")
            onStarted()
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        MainActor.assumeIsolated {
            restoring = true
            onRestore()
        }
        completionHandler(true)
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isActive = false
            let wasRestore = restoring
            restoring = false
            AppLog.info(.pip, "stopped (\(wasRestore ? "back to the player" : "closed"))")
            if !wasRestore { onClosed() }
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        MainActor.assumeIsolated { AppLog.error(.pip, "failed to start: \(error.localizedDescription)") }
    }
}
