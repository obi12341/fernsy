import AVFoundation
import CFFShim
import CoreMedia
import FernsyCore

/// The video renderer's receiver (macOS 27 API). A receiver is not thread-safe; every call goes
/// through this sink under a lock, so the session's output thread, the control queue and the
/// Picture in Picture loading card can share it.
///
/// Fernsy paces its output itself (video at most 0.3 s ahead of the clock), so frames are
/// enqueued immediately; the result tells whether the decoder needs a restart.
public final class VideoSink: @unchecked Sendable {
    public enum Outcome {
        case enqueued
        case decodeFailures(Int)
        /// The renderer was flushed while the frame was on its way (expected around seeks).
        case flushedMeanwhile
        /// The decoder needs a flush and a key frame before it can show anything again.
        case needsFlush(String)
    }

    private let lock = NSLock()
    private let receiver: AVSampleBufferVideoRenderer.Receiver

    public init(receiver: sending AVSampleBufferVideoRenderer.Receiver) {
        self.receiver = receiver
    }

    public func enqueue(_ sample: CMSampleBuffer) -> Outcome {
        let ready = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>(unsafeBuffer: sample)
        lock.lock()
        defer { lock.unlock() }
        #if DEBUG
        if let simulated = simulatedOutcome() { return simulated }
        #endif
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

    public func flush() {
        lock.lock()
        defer { lock.unlock() }
        receiver.flush()
    }

    #if DEBUG
    // Test switches, counted from the first frame:
    // IPTV_TESTFLUSHREQUIRED=<s>[:<count>] reports "needs a flush" after s seconds (count times,
    // 3 s apart) – the engine recovers, and gives up after three in 30 s;
    // IPTV_TESTDECODEFAIL=<n> reports n frames that failed to decode, 5 s after the first frame.
    private var testStart: Date?
    private var testFlushes = 0
    private var testDecodeFailReported = false

    private func simulatedOutcome() -> Outcome? {
        let env = ProcessInfo.processInfo.environment
        let start = testStart ?? Date()
        testStart = start
        let elapsed = Date().timeIntervalSince(start)
        if let spec = env["IPTV_TESTFLUSHREQUIRED"]?.split(separator: ":").compactMap({ Double($0) }), let first = spec.first {
            let count = spec.count > 1 ? Int(spec[1]) : 1
            if testFlushes < count, elapsed >= first + Double(testFlushes) * 3 {
                testFlushes += 1
                return .needsFlush("[test] simulated decoder restart \(testFlushes)/\(count)")
            }
        }
        if let n = env["IPTV_TESTDECODEFAIL"].flatMap(Int.init), !testDecodeFailReported, elapsed >= 5 {
            testDecodeFailReported = true
            return .decodeFailures(n)
        }
        return nil
    }
    #endif

    /// Flush and remove the frame on screen (stopping playback). The receiver's variant is
    /// async; it runs on its own and nothing is enqueued meanwhile (the session is stopped).
    public func flushRemovingImage() {
        let receiver = receiver
        Task { await receiver.flush(removingDisplayedImage: true) }
    }

    /// Rendering events after enqueuing stopped (for example while paused): the decoder may
    /// still report that it needs a flush.
    public func observeEvents(needsFlush: @escaping @Sendable (String) -> Void,
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
public final class AudioSink: @unchecked Sendable {
    public enum Outcome {
        case enqueued
        /// The renderer suggests refilling (the output device changed, or the renderer failed).
        case suggestsFlush
        case flushedMeanwhile
    }

    private let lock = NSLock()
    private let receiver: AVSampleBufferAudioRenderer.Receiver

    public init(receiver: sending AVSampleBufferAudioRenderer.Receiver) {
        self.receiver = receiver
    }

    public func enqueue(_ sample: CMSampleBuffer) -> Outcome {
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

    public func flush() {
        lock.lock()
        defer { lock.unlock() }
        receiver.flush()
    }

    /// Automatic flushes after enqueuing stopped (output device changed while paused).
    public func observeEvents(_ handler: @escaping @Sendable () -> Void) -> Task<Void, Never> {
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
