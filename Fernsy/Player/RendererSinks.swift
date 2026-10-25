import AVFoundation
import CoreMedia

/// The video renderer's receiver (macOS 27 API). A receiver is not thread-safe; every call goes
/// through this sink under a lock, so the session's output thread, the control queue and the
/// Picture in Picture loading card can share it.
///
/// Fernsy paces its output itself (video at most 0.3 s ahead of the clock), so frames are
/// enqueued immediately; the result tells whether the decoder needs a restart.
final class VideoSink: @unchecked Sendable {
    enum Outcome {
        case enqueued
        case decodeFailures(Int)
        /// The renderer was flushed while the frame was on its way (expected around seeks).
        case flushedMeanwhile
        /// The decoder needs a flush and a key frame before it can show anything again.
        case needsFlush(String)
    }

    private let lock = NSLock()
    private let receiver: AVSampleBufferVideoRenderer.Receiver

    init(receiver: sending AVSampleBufferVideoRenderer.Receiver) {
        self.receiver = receiver
    }

    func enqueue(_ sample: CMSampleBuffer) -> Outcome {
        let ready = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(unsafeBuffer: sample)
        lock.lock()
        defer { lock.unlock() }
        switch receiver.enqueueImmediately(ready) {
        case .enqueued: return .enqueued
        case .enqueuedWithDecodeFailures(let errors): return .decodeFailures(errors.count)
        case .cancelledDueToFlush: return .flushedMeanwhile
        case .cancelledDueToFlushRequiredToResume(let error): return .needsFlush(error.localizedDescription)
        // A failed renderer is reset by a flush, like a decoder that needs one.
        case .cancelledDueToError(let error): return .needsFlush(error.localizedDescription)
        @unknown default: return .enqueued
        }
    }

    func flush() {
        lock.lock()
        defer { lock.unlock() }
        receiver.flush()
    }

    /// Flush and remove the frame on screen (stopping playback). The receiver's variant is
    /// async; it runs on its own and nothing is enqueued meanwhile (the session is stopped).
    func flushRemovingImage() {
        let receiver = receiver
        Task { await receiver.flush(removingDisplayedImage: true) }
    }

    /// Rendering events after enqueuing stopped (for example while paused): the decoder may
    /// still report that it needs a flush.
    func observeEvents(needsFlush: @escaping @Sendable (String) -> Void,
                       decodeFailures: @escaping @Sendable (Int) -> Void) -> Task<Void, Never> {
        let receiver = receiver
        return Task {
            for await event in receiver.renderingEventsAfterFinishedEnqueuing {
                switch event {
                case .requiresFlushToResumeDecoding(let error), .failed(let error): needsFlush(error.localizedDescription)
                case .didFailToDecode(let errors): decodeFailures(errors.count)
                @unknown default: break
                }
            }
        }
    }
}

/// The audio renderer's receiver, the same way as `VideoSink`.
final class AudioSink: @unchecked Sendable {
    enum Outcome {
        case enqueued
        /// The renderer suggests refilling (the output device changed, or the renderer failed).
        case suggestsFlush
        case flushedMeanwhile
    }

    private let lock = NSLock()
    private let receiver: AVSampleBufferAudioRenderer.Receiver

    init(receiver: sending AVSampleBufferAudioRenderer.Receiver) {
        self.receiver = receiver
    }

    func enqueue(_ sample: CMSampleBuffer) -> Outcome {
        let ready = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(unsafeBuffer: sample)
        lock.lock()
        defer { lock.unlock() }
        switch receiver.enqueueImmediately(ready) {
        case .enqueued: return .enqueued
        case .enqueuedWithSuggestedFlush: return .suggestsFlush
        case .cancelledDueToFlush: return .flushedMeanwhile
        case .cancelledDueToError: return .suggestsFlush
        @unknown default: return .enqueued
        }
    }

    func flush() {
        lock.lock()
        defer { lock.unlock() }
        receiver.flush()
    }

    /// Automatic flushes after enqueuing stopped (output device changed while paused).
    func observeEvents(_ handler: @escaping @Sendable () -> Void) -> Task<Void, Never> {
        let receiver = receiver
        return Task {
            for await event in receiver.renderingEventsAfterFinishedEnqueuing {
                switch event {
                case .wasFlushedAutomatically, .outputConfigurationChanged, .failed: handler()
                @unknown default: break
                }
            }
        }
    }
}
