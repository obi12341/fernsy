import CFFShim
import FernsyCore
import Foundation

/// What PlaybackSession reads from: the network (HTTPByteSource), the timeshift buffer of
/// a tuned channel (BufferByteSource), a recording on disk (FileByteSource) or in Fernsy Cloud
/// (CloudByteSource).
public protocol ByteSource: AnyObject {
    var isCancelled: Bool { get }
    var supportsRanges: Bool { get }
    var finalURL: URL? { get }
    var mimeType: String? { get }
    var netStats: HTTPByteSource.NetStats { get }
    var totalBytesReceived: Int64 { get }
    /// Sees every byte handed to FFmpeg, in order (used by TSAudioTap). Demux thread only.
    var tap: ((UnsafeBufferPointer<UInt8>) -> Void)? { get set }
    /// Live: called when the reader reaches the first byte of a reconnected stream.
    var onRejoin: ((Int64) -> Void)? { get set }

    func open() throws
    func cancel()
    func read(into ptr: UnsafeMutablePointer<UInt8>, size: Int) -> Int32
    func seek(offset: Int64, whence: Int32) -> Int64
    func reportPlaybackAhead(_ seconds: Double)
    /// Why reading failed, when the source knows better than "Connection lost" (a damaged cloud recording).
    var failureMessage: String? { get }
}

extension ByteSource {
    public var failureMessage: String? { nil }
}

extension HTTPByteSource: ByteSource {}

/// Plays the timeshift buffer of a tuned channel. Offsets are relative to the oldest byte the
/// buffer held when the reader opened (FFmpeg starts counting at 0); reading at the live edge
/// waits for the tuner instead of ending.
public final class BufferByteSource: ByteSource {
    public let buffer: TimeshiftBuffer
    private let reader: TimeshiftBuffer.Reader
    private let base: Int64
    private let lock = NSLock()
    private var cancelled = false

    public var tap: ((UnsafeBufferPointer<UInt8>) -> Void)?
    public var onRejoin: ((Int64) -> Void)?

    public init(buffer: TimeshiftBuffer) {
        self.buffer = buffer
        base = buffer.oldestOffset
        reader = buffer.makeReader(at: base)
    }

    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    public var supportsRanges: Bool { true }
    public var finalURL: URL? { nil }
    public var mimeType: String? { "video/mp2t" }
    public var netStats: HTTPByteSource.NetStats { buffer.netStats() }
    public var totalBytesReceived: Int64 { buffer.totalBytesReceived() }

    /// Logical buffer offset ↔ FFmpeg position.
    public func position(ofBufferOffset offset: Int64) -> Int64 { max(0, offset - base) }

    public func open() throws {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        reader.cancel()
    }

    public func read(into ptr: UnsafeMutablePointer<UInt8>, size: Int) -> Int32 {
        switch reader.read(into: ptr, size: size) {
        case .data(let n):
            tap?(UnsafeBufferPointer(start: ptr, count: n))
            return Int32(n)
        case .cancelled: return Int32(ffs_error_exit())
        case .ended: return Int32(ffs_error_eof())
        case .lost: return Int32(ffs_error_eio())
        }
    }

    public func seek(offset: Int64, whence: Int32) -> Int64 {
        if whence & Int32(ffs_avseek_size()) != 0 { return -1 }
        let mode = whence & ~Int32(ffs_avseek_force())
        let target: Int64
        switch mode {
        case SEEK_SET: target = base + offset
        case SEEK_CUR: target = reader.offset + offset
        default: return -1
        }
        guard reader.seek(to: target) else { return -1 }
        return target - base
    }

    public func reportPlaybackAhead(_ seconds: Double) {}
}

/// A finished or still growing recording on disk.
public final class FileByteSource: ByteSource {
    public let url: URL
    /// While true, reading at the end waits for more data (recording in progress).
    private let isGrowing: () -> Bool
    private var handle: FileHandle?
    private var offset: Int64 = 0
    private let lock = NSLock()
    private var cancelled = false

    public var tap: ((UnsafeBufferPointer<UInt8>) -> Void)?
    public var onRejoin: ((Int64) -> Void)?

    public init(url: URL, isGrowing: @escaping () -> Bool) {
        self.url = url
        self.isGrowing = isGrowing
    }

    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    public var supportsRanges: Bool { true }
    public var finalURL: URL? { url }
    public var mimeType: String? { "video/mp2t" }
    public var netStats: HTTPByteSource.NetStats { HTTPByteSource.NetStats() }
    public var totalBytesReceived: Int64 { offset }

    public func open() throws {
        handle = try FileHandle(forReadingFrom: url)
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private var fileSize: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    public func read(into ptr: UnsafeMutablePointer<UInt8>, size: Int) -> Int32 {
        guard let handle else { return Int32(ffs_error_eio()) }
        while true {
            if isCancelled { return Int32(ffs_error_exit()) }
            let n = pread(handle.fileDescriptor, ptr, size, off_t(offset))
            if n > 0 {
                offset += Int64(n)
                tap?(UnsafeBufferPointer(start: ptr, count: n))
                return Int32(n)
            }
            if n < 0 { return Int32(ffs_error_eio()) }
            guard isGrowing() else { return Int32(ffs_error_eof()) }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    public func seek(offset target: Int64, whence: Int32) -> Int64 {
        if whence & Int32(ffs_avseek_size()) != 0 { return isGrowing() ? -1 : fileSize }
        let mode = whence & ~Int32(ffs_avseek_force())
        let position: Int64
        switch mode {
        case SEEK_SET: position = target
        case SEEK_CUR: position = offset + target
        case SEEK_END: position = fileSize + target
        default: return -1
        }
        guard position >= 0 else { return -1 }
        offset = position
        return position
    }

    public func reportPlaybackAhead(_ seconds: Double) {}
}
