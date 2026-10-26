import Foundation

/// Remembers recently played packets by content, with their position on the output timeline.
///
/// Live reconnects can land on another backend of the provider's load balancer, which stamps
/// the same channel with an unrelated clock. The packets themselves are byte-identical, so a
/// replayed packet found here tells both that it is a duplicate and how far the clocks are apart.
public struct ContentHistory: Sendable {
    private var entries: [Int: (time: Double, slot: Int)] = [:]
    private var ring: [Int]
    private var next = 0

    public init(capacity: Int) {
        ring = [Int](repeating: 0, count: capacity)
    }

    /// Hash over the first bytes and the size: cheap for multi-megabyte UHD keyframes and
    /// still unique enough for compressed media.
    public static func key(_ data: UnsafeRawBufferPointer, salt: Int) -> Int {
        var hasher = Hasher()
        hasher.combine(salt)
        hasher.combine(data.count)
        hasher.combine(bytes: UnsafeRawBufferPointer(rebasing: data.prefix(2048)))
        return hasher.finalize()
    }

    public func time(of key: Int) -> Double? {
        entries[key]?.time
    }

    /// A key seen again later (e.g. silence) points at its latest occurrence.
    public mutating func insert(_ key: Int, time: Double) {
        let evicted = ring[next]
        if entries[evicted]?.slot == next { entries[evicted] = nil }
        ring[next] = key
        entries[key] = (time, next)
        next = (next + 1) % ring.count
    }

    public mutating func removeAll() {
        entries.removeAll()
        ring = [Int](repeating: 0, count: ring.count)
        next = 0
    }
}
