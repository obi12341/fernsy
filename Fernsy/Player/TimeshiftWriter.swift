import Foundation

/// Receives the cleaned packets of a tuner session (PlaybackSession in `.tuner` mode) on its
/// demux thread.
protocol TunerOutput: AnyObject {
    /// Streams of a (re)opened connection. `tappedAudio`: TSAudioTap delivers ADTS AAC as
    /// input index `PlaybackSession.tappedAudioIndex`. Returns false when the streams cannot
    /// be written (unsupported codec); the tuner then gives up on timeshift.
    func streamsOpened(_ fmt: UnsafeMutablePointer<AVFormatContext>, kept: [Int32], clock: Int32, tappedAudio: Bool) -> Bool
    /// The caller still owns the packet.
    func packet(_ pkt: UnsafeMutablePointer<AVPacket>, input: Int32, timeBase: AVRational)
}

private func writeToBuffer(_ opaque: UnsafeMutableRawPointer?, _ buf: UnsafePointer<UInt8>?, _ size: Int32) -> Int32 {
    guard let opaque, let buf, size > 0 else { return size }
    Unmanaged<TimeshiftWriter>.fromOpaque(opaque).takeUnretainedValue().buffer.append(UnsafeRawBufferPointer(start: buf, count: Int(size)))
    return size
}

/// Remuxes a tuner's packets into its TimeshiftBuffer on one continuous timeline.
///
/// Live feeds jump (encoder restarts, splices, a full reconnect landing on a backend with
/// another clock). The muxer needs strictly increasing timestamps, and seeking needs one
/// timeline, so every jump of the clock stream (video, or audio for radio) starts a new
/// epoch whose offset continues right after what was written. Other streams follow the
/// epoch that places them next to their own last packet, so packets still interleaved from
/// before a jump land correctly.
final class TimeshiftWriter: TunerOutput, @unchecked Sendable {
    let buffer: TimeshiftBuffer
    private let lock = NSLock()
    private var muxer: OpaquePointer?
    private var failed = false

    private struct Output {
        let type: AVMediaType
        let codec: AVCodecID
        var last: Double?
        var lastDTS: Int64 = .min
        var rejected = 0
        /// A stream with a discontinuity of its own (the clock stream did not jump with it).
        var ownOffset: Double?
    }

    private var outputs: [Output] = []
    /// Input stream index of the current connection → output index.
    private var mapping: [Int32: Int] = [:]
    private var clockInput: Int32 = -1
    /// Seconds subtracted from input time: current epoch first.
    private var epochs: [Double] = []
    private var lastResync: Double = -.infinity
    private var started = false
    /// After a reconnect the server replays what it had buffered: going back in time is a
    /// repeat then, not a discontinuity.
    private var replayUntil = Date.distantPast
    #if DEBUG
    private let createdAt = Date()
    /// IPTV_TESTJUMP=<after s>:<seconds>: shift the input clock like an ad splice does.
    private let testJump = ProcessInfo.processInfo.environment["IPTV_TESTJUMP"]?.split(separator: ":").compactMap { Double($0) }
    #endif

    init(buffer: TimeshiftBuffer) {
        self.buffer = buffer
    }

    deinit {
        close()
    }

    /// Writes the trailer and closes the buffer for readers.
    func close() {
        lock.lock()
        if muxer != nil {
            var m: OpaquePointer? = muxer
            ffs_mux_free(&m)
            muxer = nil
        }
        lock.unlock()
        buffer.close()
    }

    var isFailed: Bool {
        lock.lock(); defer { lock.unlock() }
        return failed
    }

    // MARK: TunerOutput

    func streamsOpened(_ fmt: UnsafeMutablePointer<AVFormatContext>, kept: [Int32], clock: Int32, tappedAudio: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !failed else { return false }
        mapping = [:]
        clockInput = clock
        var inputs: [(index: Int32, type: AVMediaType, codec: AVCodecID, par: UnsafeMutablePointer<AVCodecParameters>?, language: String?)] = []
        for index in kept {
            guard let st = fmt.pointee.streams[Int(index)] else { continue }
            let par = st.pointee.codecpar!
            let language = ffs_metadata(st.pointee.metadata, "language").map { String(cString: $0) }
            inputs.append((index, par.pointee.codec_type, par.pointee.codec_id, par, language))
        }
        if tappedAudio {
            inputs.append((PlaybackSession.tappedAudioIndex, AVMEDIA_TYPE_AUDIO, AV_CODEC_ID_AAC, nil, nil))
        }

        if muxer == nil {
            let opaque = Unmanaged.passUnretained(self).toOpaque()
            guard let m = ffs_mux_alloc(opaque, writeToBuffer) else { failed = true; return false }
            for input in inputs {
                let out: Int32
                if let par = input.par {
                    out = ffs_mux_add_stream(m, par, input.language)
                } else {
                    out = ffs_mux_add_aac(m, 48000, 2)
                }
                guard out >= 0 else { continue }
                mapping[input.index] = outputs.count
                outputs.append(Output(type: input.type, codec: input.codec))
            }
            guard !outputs.isEmpty, ffs_mux_begin(m) >= 0 else {
                var dead: OpaquePointer? = m
                ffs_mux_free(&dead)
                failed = true
                #if DEBUG
                debugLog("[timeshift] muxer refused the streams, timeshift off for this channel")
                #endif
                return false
            }
            muxer = m
            return true
        }

        // A new connection: continue in the existing outputs, matched by kind in order.
        replayUntil = Date().addingTimeInterval(15)
        var used = Set<Int>()
        for input in inputs {
            if let out = outputs.indices.first(where: { !used.contains($0) && outputs[$0].type == input.type && outputs[$0].codec == input.codec }) {
                used.insert(out)
                mapping[input.index] = out
            }
        }
        #if DEBUG
        debugLog("[timeshift] new connection mapped \(mapping.count) of \(inputs.count) streams")
        #endif
        return !mapping.isEmpty
    }

    func packet(_ pkt: UnsafeMutablePointer<AVPacket>, input: Int32, timeBase: AVRational) {
        lock.lock()
        defer { lock.unlock() }
        guard let muxer, let out = mapping[input] else { return }
        let raw = pkt.pointee.dts != ffs_nopts() ? pkt.pointee.dts : pkt.pointee.pts
        guard raw != ffs_nopts() else { return }
        let tb = av_q2d(timeBase)
        #if DEBUG
        if let jump = testJump, jump.count == 2, Date().timeIntervalSince(createdAt) > jump[0] {
            let delta = Int64((jump[1] / tb).rounded())
            if pkt.pointee.pts != ffs_nopts() { pkt.pointee.pts += delta }
            if pkt.pointee.dts != ffs_nopts() { pkt.pointee.dts += delta }
            let shifted = raw + delta
            return write(pkt, raw: shifted, out: out, input: input, muxer: muxer, timeBase: timeBase, tb: tb)
        }
        #endif
        write(pkt, raw: raw, out: out, input: input, muxer: muxer, timeBase: timeBase, tb: tb)
    }

    private func write(_ pkt: UnsafeMutablePointer<AVPacket>, raw: Int64, out: Int, input: Int32, muxer: OpaquePointer,
                       timeBase: AVRational, tb: Double) {
        let t = Double(raw) * tb
        let isClock = input == clockInput
        let isKey = pkt.pointee.flags & AV_PKT_FLAG_KEY != 0

        guard let offset = place(t, out: out, isClock: isClock, isKey: isKey) else { return }
        let shift = Int64((offset / tb).rounded())
        if pkt.pointee.pts != ffs_nopts() { pkt.pointee.pts -= shift }
        if pkt.pointee.dts != ffs_nopts() { pkt.pointee.dts -= shift }
        let time = t - offset

        // Strictly increasing DTS per stream, in the muxer's 90 kHz.
        let dts90 = Int64((Double(pkt.pointee.dts != ffs_nopts() ? pkt.pointee.dts : pkt.pointee.pts) * tb * 90_000).rounded())
        guard dts90 > outputs[out].lastDTS else { return }

        // Resync points: video keyframes; radio once a second.
        let resync = isClock && (outputs[out].type == AVMEDIA_TYPE_VIDEO ? isKey : time - lastResync >= 1)
        if resync {
            ffs_mux_flush(muxer)
            buffer.markResyncPoint(time: time)
            lastResync = time
            started = true
        }
        guard started else { return }
        outputs[out].lastDTS = dts90
        outputs[out].last = time
        if ffs_mux_write(muxer, pkt, Int32(out), timeBase, resync ? 1 : 0) < 0 {
            #if DEBUG
            debugLog("[timeshift] write failed for stream \(out) at \(String(format: "%.2f", time))")
            #endif
        }
    }

    /// The epoch offset for this packet, or nil to drop it.
    private func place(_ t: Double, out: Int, isClock: Bool, isKey: Bool) -> Double? {
        let newest = outputs.compactMap(\.last).max()
        guard let current = epochs.first else {
            // The timeline starts with a keyframe of the clock stream, one second in.
            guard isClock, isKey || outputs[out].type != AVMEDIA_TYPE_VIDEO else { return nil }
            epochs = [t - 1]
            return epochs[0]
        }
        guard let last = outputs[out].last else {
            // First packet of this output: it belongs next to what the others wrote.
            let time = t - current
            if let newest, time < newest - 2 || time > newest + 10 {
                return isClock ? newEpoch(t, after: newest) : reject(t, out: out, after: newest)
            }
            return current
        }
        for offset in epochs + [outputs[out].ownOffset].compactMap({ $0 }) {
            let d = (t - offset) - last
            if d > 0 && d <= 10 {
                outputs[out].rejected = 0
                return offset
            }
        }
        let d = (t - current) - last
        if isClock {
            // The same instant again, or what a reconnect replays, is dropped. Any other jump –
            // backwards too, e.g. an ad splice with its own clock – starts a new epoch.
            if d <= 0 && d > -1 { return nil }
            if d <= 0 && d >= -60 && Date() < replayUntil { return nil }
            return newEpoch(t, after: newest ?? last)
        }
        return reject(t, out: out, after: newest ?? last)
    }

    /// A non-clock packet that fits nowhere. A stream that keeps not fitting has its own
    /// discontinuity: it continues next to the others on an offset of its own.
    private func reject(_ t: Double, out: Int, after newest: Double) -> Double? {
        outputs[out].rejected += 1
        guard outputs[out].rejected > 100 else { return nil }
        outputs[out].rejected = 0
        let offset = t - (newest + 0.02)
        outputs[out].ownOffset = offset
        #if DEBUG
        debugLog("[timeshift] stream \(out) jumped on its own, continues at \(String(format: "%.2f", newest)) s")
        #endif
        return offset
    }

    private func newEpoch(_ t: Double, after newest: Double) -> Double {
        let offset = t - (newest + 0.04)
        epochs = [offset] + epochs.prefix(1)
        #if DEBUG
        debugLog("[timeshift] timeline jump, new epoch at \(String(format: "%.2f", newest + 0.04)) s")
        #endif
        return offset
    }
}
