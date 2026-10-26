import CFFShim
import FernsyCore
import Foundation

/// The remuxed MPEG-TS stream of one tuned channel, kept on disk for timeshift and
/// recordings.
///
/// One logical byte stream, stored as segment files. Segments start at resync points
/// (video keyframes with PAT/PMT in front), so the oldest retained byte is always a valid
/// place to start demuxing. An in-memory index maps buffer time (the tuner's continuous
/// timeline) and wall-clock time to byte offsets of resync points.
public final class TimeshiftBuffer {
    public struct Entry {
        /// Buffer time in seconds (continuous across reconnects).
        public let time: Double
        /// When this point arrived; for clock times in the UI and recording start/end.
        public let wall: Date
        public let offset: Int64
    }

    public enum ReadResult {
        case data(Int)
        /// The tuner stopped and everything has been read.
        case ended
        case cancelled
        /// The position was trimmed away (paused longer than the buffer allows).
        case lost
    }

    public let directory: URL
    /// Seconds kept behind the live edge (at least two minutes, needed for playback).
    public var keepSeconds: Double {
        get { cond.lock(); defer { cond.unlock() }; return keep }
        set { cond.lock(); keep = max(120, newValue); cond.unlock() }
    }

    private struct Segment {
        let start: Int64
        let url: URL
        let fd: Int32
    }

    private let cond = NSCondition()
    private var keep: Double
    private var segments: [Segment] = []
    private var entries: [Entry] = []
    private var writeOffset: Int64 = 0
    private var closed = false
    private var failed = false
    private var readerOffsets: [Int: Int64] = [:]
    private var nextReaderID = 0
    private let segmentBytes: Int64 = 64 << 20
    private var statsProvider: (() -> (HTTPByteSource.NetStats, Int64))?

    public init(channelId: Int, keepSeconds: Double) {
        keep = max(120, keepSeconds)
        directory = Self.root.appendingPathComponent("\(channelId)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        openSegment(at: 0)
    }

    deinit {
        for segment in segments { Darwin.close(segment.fd) }
        try? FileManager.default.removeItem(at: directory)
    }

    public static var root: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fernsy/timeshift", isDirectory: true)
    }

    /// Leftovers of a previous run (crash, force quit).
    public static func removeLeftovers() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Writing (tuner demux thread)

    public func append(_ bytes: UnsafeRawBufferPointer) {
        guard let base = bytes.baseAddress, bytes.count > 0 else { return }
        cond.lock()
        defer { cond.unlock() }
        guard !failed, let segment = segments.last else { return }
        var done = 0
        while done < bytes.count {
            let n = Darwin.write(segment.fd, base.advanced(by: done), bytes.count - done)
            if n <= 0 {
                // Disk full or similar: stop growing, readers run into the end.
                failed = true
                break
            }
            done += n
        }
        writeOffset += Int64(done)
        cond.broadcast()
    }

    /// The next byte written starts a resync point at buffer time `time`.
    public func markResyncPoint(time: Double) {
        cond.lock()
        defer { cond.unlock() }
        guard !failed else { return }
        if let last = entries.last, time <= last.time { return }
        if let current = segments.last, writeOffset - current.start >= segmentBytes {
            openSegment(at: writeOffset)
        }
        entries.append(Entry(time: time, wall: Date(), offset: writeOffset))
        trim()
        cond.broadcast()
    }

    /// No more data will come; readers get `.ended` once they reach the end.
    public func close() {
        cond.lock()
        closed = true
        cond.broadcast()
        cond.unlock()
    }

    public func setStatsProvider(_ provider: @escaping () -> (HTTPByteSource.NetStats, Int64)) {
        cond.lock()
        statsProvider = provider
        cond.unlock()
    }

    public func netStats() -> HTTPByteSource.NetStats {
        cond.lock()
        let provider = statsProvider
        cond.unlock()
        return provider?().0 ?? HTTPByteSource.NetStats()
    }

    public func totalBytesReceived() -> Int64 {
        cond.lock()
        let provider = statsProvider
        cond.unlock()
        return provider?().1 ?? 0
    }

    private func openSegment(at offset: Int64) {
        let url = directory.appendingPathComponent("\(offset).ts")
        let fd = Darwin.open(url.path, O_RDWR | O_CREAT | O_TRUNC | O_APPEND, 0o644)
        guard fd >= 0 else {
            failed = true
            return
        }
        segments.append(Segment(start: offset, url: url, fd: fd))
    }

    /// Drops whole segments that lie entirely outside the window. Segments a reader is still
    /// in are kept, up to twice the window (a long pause); beyond that the reader loses them.
    private func trim() {
        guard let live = entries.last?.time else { return }
        let oldestReader = readerOffsets.values.min() ?? .max
        while segments.count > 1 {
            let next = segments[1].start
            guard let nextTime = entries.first(where: { $0.offset >= next })?.time else { break }
            let outside = nextTime < live - keep
            let wayOutside = nextTime < live - 2 * keep
            guard wayOutside || (outside && oldestReader >= next) else { break }
            let segment = segments.removeFirst()
            Darwin.close(segment.fd)
            try? FileManager.default.removeItem(at: segment.url)
            if let firstKept = entries.firstIndex(where: { $0.offset >= next }), firstKept > 0 {
                entries.removeFirst(firstKept)
            }
        }
    }

    // MARK: Index

    public var oldestOffset: Int64 {
        cond.lock(); defer { cond.unlock() }
        return segments.first?.start ?? 0
    }

    public var oldest: Entry? {
        cond.lock(); defer { cond.unlock() }
        return entries.first
    }

    public var newest: Entry? {
        cond.lock(); defer { cond.unlock() }
        return entries.last
    }

    public var isClosed: Bool {
        cond.lock(); defer { cond.unlock() }
        return closed
    }

    /// The last resync point at or before `time` (or the oldest one).
    public func entry(atOrBefore time: Double) -> Entry? {
        cond.lock(); defer { cond.unlock() }
        guard !entries.isEmpty else { return nil }
        var lo = 0, hi = entries.count - 1
        if entries[0].time >= time { return entries[0] }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if entries[mid].time <= time { lo = mid } else { hi = mid - 1 }
        }
        return entries[lo]
    }

    public func entry(atOrBeforeWall wall: Date) -> Entry? {
        cond.lock(); defer { cond.unlock() }
        guard let first = entries.first else { return nil }
        return entries.last { $0.wall <= wall } ?? first
    }

    /// Wall-clock time of a buffer time, interpolated from the nearest resync point.
    public func wallTime(of time: Double) -> Date? {
        guard let entry = entry(atOrBefore: time) else { return nil }
        return entry.wall.addingTimeInterval(time - entry.time)
    }

    /// Waits until the buffer has at least `seconds` of content (or the tuner gave up).
    public func waitForContent(seconds: Double, timeout: TimeInterval, cancelled: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        cond.lock()
        defer { cond.unlock() }
        while !cancelled() && !closed && Date() < deadline {
            if let first = entries.first, let last = entries.last, last.time - first.time >= seconds { return true }
            cond.wait(until: min(deadline, Date().addingTimeInterval(0.25)))
        }
        return !entries.isEmpty
    }

    // MARK: Reading

    public func makeReader(at offset: Int64) -> Reader {
        cond.lock()
        defer { cond.unlock() }
        let id = nextReaderID
        nextReaderID += 1
        readerOffsets[id] = offset
        return Reader(buffer: self, id: id)
    }

    /// One position in the buffer; keeps its segment from being trimmed.
    public final class Reader {
        private let buffer: TimeshiftBuffer
        private let id: Int
        private var cancelled = false

        fileprivate init(buffer: TimeshiftBuffer, id: Int) {
            self.buffer = buffer
            self.id = id
        }

        deinit {
            buffer.cond.lock()
            buffer.readerOffsets[id] = nil
            buffer.cond.unlock()
        }

        public var offset: Int64 {
            buffer.cond.lock(); defer { buffer.cond.unlock() }
            return buffer.readerOffsets[id] ?? 0
        }

        public func cancel() {
            buffer.cond.lock()
            cancelled = true
            buffer.cond.broadcast()
            buffer.cond.unlock()
        }

        public func seek(to offset: Int64) -> Bool {
            buffer.cond.lock(); defer { buffer.cond.unlock() }
            guard offset >= (buffer.segments.first?.start ?? 0), offset <= buffer.writeOffset else { return false }
            buffer.readerOffsets[id] = offset
            return true
        }

        /// Blocks until data is available at the current position.
        public func read(into ptr: UnsafeMutableRawPointer, size: Int) -> ReadResult {
            let b = buffer
            b.cond.lock()
            defer { b.cond.unlock() }
            while true {
                if cancelled { return .cancelled }
                let offset = b.readerOffsets[id] ?? 0
                guard let index = b.segments.lastIndex(where: { $0.start <= offset }) else { return .lost }
                if offset < b.writeOffset {
                    let end = index + 1 < b.segments.count ? b.segments[index + 1].start : b.writeOffset
                    let count = Int(min(Int64(size), end - offset))
                    let n = pread(b.segments[index].fd, ptr, count, off_t(offset - b.segments[index].start))
                    guard n > 0 else { return .lost }
                    b.readerOffsets[id] = offset + Int64(n)
                    return .data(n)
                }
                if b.closed || b.failed { return .ended }
                b.cond.wait(until: Date().addingTimeInterval(0.5))
            }
        }
    }
}

/// Copies the buffer from a resync point into a recording file until stopped.
public final class RecordingCopier {
    public let url: URL
    private let reader: TimeshiftBuffer.Reader
    private let lock = NSLock()
    private var stopAt: Int64?
    private var thread: Thread?
    private let done = DispatchSemaphore(value: 0)
    public private(set) var bytesWritten: Int64 = 0
    public private(set) var error: String?
    public var onFinish: (() -> Void)?

    public init(buffer: TimeshiftBuffer, from offset: Int64, to url: URL) throws {
        self.url = url
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        reader = buffer.makeReader(at: offset)
        let thread = Thread { [self] in
            self.run(handle, buffer: buffer)
        }
        thread.name = "recording.copy"
        thread.qualityOfService = .utility
        self.thread = thread
        thread.start()
    }

    /// Writes what the buffer holds up to now, then ends the file.
    public func finish(at offset: Int64) {
        lock.lock()
        stopAt = offset
        lock.unlock()
    }

    public func cancel() {
        reader.cancel()
    }

    public func waitUntilDone() {
        done.wait()
        done.signal()
    }

    private func run(_ handle: FileHandle, buffer: TimeshiftBuffer) {
        let size = 256 * 1024
        let chunk = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        defer {
            chunk.deallocate()
            try? handle.close()
            done.signal()
            DispatchQueue.main.async { self.onFinish?() }
        }
        while true {
            lock.lock()
            let limit = stopAt
            lock.unlock()
            var want = size
            if let limit {
                let left = limit - reader.offset
                if left <= 0 { return }
                want = Int(min(Int64(size), left))
            }
            switch reader.read(into: chunk, size: want) {
            case .data(let n):
                do {
                    try handle.write(contentsOf: Data(bytesNoCopy: chunk, count: n, deallocator: .none))
                    lock.lock()
                    bytesWritten += Int64(n)
                    lock.unlock()
                } catch {
                    lock.lock()
                    self.error = error.localizedDescription
                    lock.unlock()
                    return
                }
            case .ended, .cancelled:
                return
            case .lost:
                lock.lock()
                error = String(localized: "The recording could not be written fast enough", bundle: .module)
                lock.unlock()
                return
            }
        }
    }
}

extension TimeshiftBuffer {
    /// Everything written so far ends here.
    public var endOffset: Int64 {
        cond.lock(); defer { cond.unlock() }
        return writeOffset
    }
}
