import AVKit
import Combine
import CoreImage
import CoreText
import FernsyCore
import FernsyPlayer

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
    /// `sink`: the engine's video sink, flushed once the layer is back in the player window.
    func end(flushing sink: VideoSink) {
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
            sink.flush()
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
