import FernsyCore
import Foundation

/// Extracts an ADTS AAC elementary stream from one MPEG-TS PID, bypassing FFmpeg's PES
/// assembly.
///
/// Some restream servers write a single PES header at connection start and then append
/// AAC to that PES forever (often under a PMT entry that claims AC-3). FFmpeg only
/// emits such a PES once ~200 KB have piled up, i.e. ~12 s late, so audio never makes
/// it in time. This tap sees the raw bytes on their way into FFmpeg, splits the AAC
/// into ADTS frames and timestamps them from the PES PTS plus the running sample count.
final class TSAudioTap {
    struct Frame {
        let data: Data
        /// 90 kHz units, same clock as FFmpeg's MPEG-TS timestamps. Nil after a reconnect
        /// until the next PES header: the receiver places such frames itself.
        let pts: Int64?
        let duration: Int64
    }

    let pid: Int
    var onFrame: ((Frame) -> Void)?

    private var carry = [UInt8]()
    private var es = [UInt8]()
    private var nextPTS: Int64?
    private(set) var sampleRate = 0
    private(set) var channels = 0

    /// Frames are only handed out without a timestamp after a reconnect (not at startup).
    private var rejoined = false

    private static let sampleRates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]

    init(pid: Int) {
        self.pid = pid
    }

    /// The byte stream restarts (live reconnect): nothing before this point continues.
    /// Frames are handed out without timestamp until the next PES header, which this kind of
    /// stream carries only every few seconds.
    func reset() {
        carry.removeAll(keepingCapacity: true)
        es.removeAll(keepingCapacity: true)
        nextPTS = nil
        rejoined = true
    }

    func feed(_ bytes: UnsafeBufferPointer<UInt8>) {
        carry.append(contentsOf: bytes)
        var offset = 0
        let count = carry.count
        carry.withUnsafeBufferPointer { buf in
            while offset + 188 <= count {
                if buf[offset] != 0x47 {
                    // Lost sync: find the next 0x47 that is followed by another one 188 bytes later.
                    var next = offset + 1
                    while next + 188 < count && !(buf[next] == 0x47 && buf[next + 188] == 0x47) { next += 1 }
                    if next + 188 >= count {
                        offset = next
                        break
                    }
                    offset = next
                }
                handlePacket(buf, at: offset)
                offset += 188
            }
        }
        carry.removeFirst(min(offset, carry.count))
    }

    private func handlePacket(_ p: UnsafeBufferPointer<UInt8>, at i: Int) {
        let packetPID = (Int(p[i + 1] & 0x1f) << 8) | Int(p[i + 2])
        guard packetPID == pid else { return }

        let unitStart = p[i + 1] & 0x40 != 0
        let adaptation = (p[i + 3] >> 4) & 0x3
        var start = i + 4
        if adaptation & 0x2 != 0 { start += 1 + Int(p[i + 4]) }
        guard adaptation & 0x1 != 0, start < i + 188 else { return }
        let end = i + 188

        if unitStart && end - start >= 9 && p[start] == 0 && p[start + 1] == 0 && p[start + 2] == 1 {
            let headerLength = Int(p[start + 8])
            if p[start + 7] & 0x80 != 0, end - start >= 14 {
                let b = start + 9
                let pts = (Int64(p[b] & 0x0e) << 29) | (Int64(p[b + 1]) << 22) | (Int64(p[b + 2] & 0xfe) << 14)
                    | (Int64(p[b + 3]) << 7) | (Int64(p[b + 4]) >> 1)
                // A new PES re-anchors the clock; a partial frame from the old one is dropped.
                es.removeAll(keepingCapacity: true)
                if nextPTS == nil { AppLog.detail(.player, "first PES on PID \(pid), pts \(Double(pts) / 90_000)") }
                nextPTS = pts
            }
            start = min(end, start + 9 + headerLength)
        }
        es.append(contentsOf: UnsafeBufferPointer(rebasing: p[start..<end]))
        extractFrames()
    }

    private func extractFrames() {
        var pos = 0
        let n = es.count
        es.withUnsafeBufferPointer { b in
            while pos + 7 <= n {
                guard b[pos] == 0xff && (b[pos + 1] & 0xf6) == 0xf0 else {
                    pos += 1
                    continue
                }
                let length = (Int(b[pos + 3] & 0x3) << 11) | (Int(b[pos + 4]) << 3) | (Int(b[pos + 5]) >> 5)
                let rateIndex = Int((b[pos + 2] >> 2) & 0xf)
                guard length >= 7, rateIndex < Self.sampleRates.count else {
                    pos += 1
                    continue
                }
                if pos + length > n { break }
                // Guard against false syncs: the following frame must start with a sync word too.
                if pos + length + 2 <= n && !(b[pos + length] == 0xff && (b[pos + length + 1] & 0xf6) == 0xf0) {
                    pos += 1
                    continue
                }
                let rate = Self.sampleRates[rateIndex]
                let blocks = Int(b[pos + 6] & 0x3) + 1
                let duration = Int64(1024 * blocks) * 90_000 / Int64(rate)
                sampleRate = rate
                channels = Int(((b[pos + 2] & 0x1) << 2) | (b[pos + 3] >> 6))
                let frame = Data(UnsafeBufferPointer(rebasing: b[pos..<(pos + length)]))
                if let pts = nextPTS {
                    onFrame?(Frame(data: frame, pts: pts, duration: duration))
                    nextPTS = (pts + duration) & 0x1_FFFF_FFFF
                } else if rejoined {
                    onFrame?(Frame(data: frame, pts: nil, duration: duration))
                }
                pos += length
            }
        }
        es.removeFirst(min(pos, es.count))
    }
}
