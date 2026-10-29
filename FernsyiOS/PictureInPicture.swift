import AVKit
import Combine
import FernsyCore
import FernsyPlayer

/// System Picture in Picture for the engine's display layer (ios-app design 5), after the Mac
/// app's controller without its macOS stage: iOS scales the sample-buffer source itself. It
/// starts from the player's button or by itself when the app leaves while playing (only then:
/// automatic start follows the engine's status, ios-pip-only-while-playing); the full-screen
/// player closes meanwhile, "back" reopens it, closing the window stops playback.
@MainActor
final class PictureInPicture: NSObject, ObservableObject {
    static let shared = PictureInPicture()

    @Published private(set) var isPossible = false
    @Published private(set) var isActive = false

    private weak var engine: PlayerEngine?
    private var controller: AVPictureInPictureController?
    private var restoring = false
    /// Playing when "back" was tapped: the full-screen player continues playing.
    private var playingBeforeRestore = false
    private var observers: Set<AnyCancellable> = []

    /// Creates the controller once for the engine (the model has one engine for the app's life).
    func attach(engine: PlayerEngine) {
        // Not every device (and no simulator) supports PiP: the controller then comes back as a
        // null object, and touching it crashes.
        guard self.engine !== engine, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        self.engine = engine
        observers = []
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: engine.displayLayer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        self.controller = controller
        // By itself only while something plays: after the player closes the controller stays,
        // and leaving the app would open an empty window.
        engine.$status.map(Self.hasPlayback).removeDuplicates().sink { [weak self] playing in
            guard let controller = self?.controller, controller.canStartPictureInPictureAutomaticallyFromInline != playing else { return }
            controller.canStartPictureInPictureAutomaticallyFromInline = playing
            AppLog.info(.pip, "automatic Picture in Picture \(playing ? "on" : "off")")
        }.store(in: &observers)
        controller.publisher(for: \.isPictureInPicturePossible).receive(on: RunLoop.main)
            .sink { [weak self] in self?.isPossible = $0 }.store(in: &observers)
        // The window shows pause state, duration and live; keep it current.
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

    /// The system reports PiP as possible before the layer shows a picture; starting then
    /// crashes inside AVKit (seen on the Mac).
    var canStart: Bool {
        isPossible && engine?.lastPicture.value != nil
    }

    /// Loading, playing, paused or buffering: the player has something to continue in the window.
    nonisolated static func hasPlayback(_ status: PlayerEngine.Status) -> Bool {
        switch status {
        case .idle, .ended, .failed: false
        case .loading, .playing, .paused, .buffering: true
        }
    }
}

extension PictureInPicture: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isActive = true
            restoring = false
            // The full-screen player closes while playback continues in the window.
            PlayerPresentation.shared.inPictureInPicture = true
            AppLog.info(.pip, "Picture in Picture starts")
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        MainActor.assumeIsolated {
            restoring = true
            playingBeforeRestore = engine.map { Self.hasPlayback($0.status) && !$0.isPaused } ?? false
            PlayerPresentation.shared.inPictureInPicture = false
            AppLog.info(.pip, "back from Picture in Picture")
        }
        completionHandler(true)
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isActive = false
            if !restoring {
                // Closed in the window: playback ends, as when closing the player.
                PlayerPresentation.shared.inPictureInPicture = false
                AppLog.info(.pip, "Picture in Picture closed")
                TVModel.shared.stop()
                Orientation.landscapeOnPhone(false)
            } else if playingBeforeRestore, let engine, engine.isPaused {
                // Back in the app the system may have paused the window's playback on the way.
                AppLog.info(.pip, "back from Picture in Picture: playback continues")
                engine.setPaused(false)
            }
            restoring = false
            playingBeforeRestore = false
        }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        MainActor.assumeIsolated {
            PlayerPresentation.shared.inPictureInPicture = false
            AppLog.warning(.pip, "Picture in Picture failed: \(error.localizedDescription)")
        }
    }
}

extension PictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        MainActor.assumeIsolated {
            // Returning to the app is no pause (ios-app "Back from Picture in Picture").
            if restoring && !playing {
                AppLog.info(.pip, "pause while returning from Picture in Picture ignored")
                return
            }
            AppLog.detail(.pip, playing ? "play from Picture in Picture" : "pause from Picture in Picture")
            engine?.setPaused(!playing)
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        MainActor.assumeIsolated {
            // Live: an unbounded range shows the live indicator instead of a scrubber.
            guard let engine, !engine.isLiveStream, !engine.isTimeshift, engine.progress.duration > 0 else {
                return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
            }
            // On the layer's clock: the item's start is the clock now minus the item position.
            let start = engine.clockTime - engine.progress.position
            return CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                               duration: CMTime(seconds: engine.progress.duration, preferredTimescale: 600))
        }
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        // A stopped engine keeps isPaused false; it must not read as playing.
        MainActor.assumeIsolated { engine.map { !Self.hasPlayback($0.status) || $0.isPaused } ?? true }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        MainActor.assumeIsolated { engine?.seek(by: skipInterval.seconds) }
        completionHandler()
    }
}
