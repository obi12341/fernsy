import Foundation

/// Thread-safe FIFO between the demuxer and a decoder thread.
/// Packets carry the playback serial they were demuxed under, so decoders can
/// discard anything that predates a seek or a stream discontinuity.
final class PacketQueue {
    enum Item {
        case packet(UnsafeMutablePointer<AVPacket>, serial: Int)
        /// Decoder must reset its state; everything after belongs to `serial`.
        case flush(serial: Int)
        /// No more packets for `serial` until the next flush.
        case eof(serial: Int)
    }

    private let cond = NSCondition()
    private var items: [Item] = []
    private var head = 0
    private var aborted = false
    private var bytes = 0

    var byteCount: Int {
        cond.lock(); defer { cond.unlock() }
        return bytes
    }

    func put(_ item: Item) {
        cond.lock()
        defer { cond.unlock() }
        if aborted {
            Self.free(item)
            return
        }
        if case .packet(let pkt, _) = item { bytes += Int(pkt.pointee.size) }
        items.append(item)
        cond.signal()
    }

    /// Blocks until an item is available. Returns nil once aborted.
    func get() -> Item? {
        cond.lock()
        defer { cond.unlock() }
        while head >= items.count && !aborted {
            cond.wait()
        }
        if aborted { return nil }
        let item = items[head]
        head += 1
        if case .packet(let pkt, _) = item { bytes -= Int(pkt.pointee.size) }
        if head > 512 && head * 2 > items.count {
            items.removeFirst(head)
            head = 0
        }
        return item
    }

    /// Drops all queued items (used before posting a flush marker).
    func clear() {
        cond.lock()
        defer { cond.unlock() }
        for i in head..<items.count { Self.free(items[i]) }
        items.removeAll(keepingCapacity: true)
        head = 0
        bytes = 0
    }

    func abort() {
        cond.lock()
        aborted = true
        for i in head..<items.count { Self.free(items[i]) }
        items.removeAll()
        head = 0
        bytes = 0
        cond.broadcast()
        cond.unlock()
    }

    private static func free(_ item: Item) {
        if case .packet(let pkt, _) = item {
            var p: UnsafeMutablePointer<AVPacket>? = pkt
            av_packet_free(&p)
        }
    }
}
