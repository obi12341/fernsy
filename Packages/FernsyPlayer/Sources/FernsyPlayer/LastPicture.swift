import CoreVideo
import Foundation

/// The newest video frame sent to the renderer (the renderer itself does not hand it out while
/// it plays): Picture in Picture starts only with a picture, and its loading picture is based on it.
public final class LastPicture: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?

    public var value: CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    public func set(_ buffer: CVPixelBuffer?) {
        lock.lock()
        self.buffer = buffer
        lock.unlock()
    }
}
