import AVFoundation
import CFFShim
import CoreMedia
import CoreVideo
import FernsyCore

/// Multi-connection live input: admission of packets from overlapping connections, duplicate
/// removal, rejoining after a reconnect, and the audio rescue for PIDs probing cannot read.
extension PlaybackSession {
    func knownRescuePIDs() -> Set<Int32> {
        Self.rescueLock.lock(); defer { Self.rescueLock.unlock() }
        let all = UserDefaults.standard.dictionary(forKey: Self.rescueStore) as? [String: [Int]] ?? [:]
        return Set((all[rescueKey] ?? []).map(Int32.init))
    }

    func rememberRescuePIDs(_ pids: Set<Int32>) {
        Self.rescueLock.lock(); defer { Self.rescueLock.unlock() }
        var all = UserDefaults.standard.dictionary(forKey: Self.rescueStore) as? [String: [Int]] ?? [:]
        all[rescueKey] = pids.isEmpty ? nil : pids.map(Int.init)
        UserDefaults.standard.set(all, forKey: Self.rescueStore)
    }

    func installAudioTap(pid: Int32) {
        let tap = TSAudioTap(pid: Int(pid))
        tap.onFrame = { [weak self] frame in self?.enqueueTapped(frame) }
        audioTap = tap
        source.tap = { [weak tap] bytes in tap?.feed(bytes) }
    }

    /// Demux thread, inside `read`: the next bytes come from a reconnected live stream.
    func rejoin(at offset: Int64) {
        audioTap?.reset()
        connections.append(Connection(start: offset, cut: connections[connections.count - 1].cut, decided: false))
        tapConnection = connections.count - 1
        tapRejoining = audioTap != nil
        AppLog.detail(.player, "rejoining live stream after reconnect at byte \(offset)")
    }

    private func countDuplicate() {
        lock.lock()
        duplicatesDropped += 1
        lock.unlock()
    }

    /// Live: drops packets a reconnected stream repeats, lines each new connection's clock up
    /// with what was played, and after a real gap holds video back until a keyframe so the
    /// decoder does not show broken references.
    func admitLive(_ pkt: UnsafeMutablePointer<AVPacket>, index: Int32, isVideo: Bool, tb: Double) -> Bool {
        guard pkt.pointee.dts != ffs_nopts() || pkt.pointee.pts != ffs_nopts() else { return !(isVideo && needKeyframe) }
        let connection = connectionIndex(of: pkt, index: index)
        #if DEBUG
        // IPTV_TESTCLOCK=<seconds>: every reconnect lands on a "backend" whose clock is that
        // much further ahead, like the provider's load balancer does.
        if debugClockSkew != 0 && connection > 0 {
            let skew = Int64(debugClockSkew * Double(connection) / tb)
            if pkt.pointee.pts != ffs_nopts() { pkt.pointee.pts += skew }
            if pkt.pointee.dts != ffs_nopts() { pkt.pointee.dts += skew }
        }
        #endif
        let raw = pkt.pointee.dts != ffs_nopts() ? pkt.pointee.dts : pkt.pointee.pts
        let streamTime = Double(raw) * tb
        // Content keys only for the stream that drives alignment (video, or audio for radio):
        // audio has too many identical frames (silence) to place reliably.
        let aligns = isVideo || !hasVideoStream
        let key = aligns && pkt.pointee.data != nil
            ? ContentHistory.key(UnsafeRawBufferPointer(start: pkt.pointee.data, count: Int(pkt.pointee.size)), salt: Int(index))
            : nil

        if connection > rejoinedConnection[index] ?? 0 {
            if let last = lastOut[index] {
                if !connections[connection].decided, let key, let known = history.time(of: key) {
                    connections[connection].cut = streamTime - known
                    connections[connection].decided = true
                    AppLog.detail(.player, "connection \(connection) lined up by content, clock offset \(String(format: "%.2f", connections[connection].cut - connections[connection - 1].cut)) s")
                    countDuplicate()
                    return false
                }
                let out = streamTime - connections[connection].cut
                if out <= last + 0.001 && last - out < 60 {
                    countDuplicate()
                    return false
                }
                let gap = out - last
                // A big jump may be another backend's clock: wait a little for a content match
                // before treating it as a real discontinuity.
                if !connections[connection].decided && (gap > 10 || gap < -60) && connections[connection].alignWait < 150 {
                    connections[connection].alignWait += 1
                    return false
                }
                AppLog.detail(.player, "rejoined \(isVideo ? "video" : "audio") stream in connection \(connection), gap \(String(format: "%.2f", gap)) s, \(duplicatesDropped) duplicates dropped so far")
                if isVideo && gap > 0.5 { needKeyframe = true }
                // The first stream to rejoin decides the cut for both, keeping them in sync.
                // Larger jumps are discontinuities and handled by a resync instead.
                if !connections[connection].decided {
                    connections[connection].decided = true
                    if gap > 0.5 && gap < 10 { connections[connection].cut += gap - 0.04 }
                }
            }
            rejoinedConnection[index] = connection
        }
        if isVideo && needKeyframe {
            guard pkt.pointee.flags & AV_PKT_FLAG_KEY != 0 else { return false }
            needKeyframe = false
        }
        let out = streamTime - connections[connection].cut
        lastOut[index] = out
        if let key { history.insert(key, time: out) }
        return true
    }

    private func connectionIndex(of pkt: UnsafeMutablePointer<AVPacket>, index: Int32) -> Int {
        let pos = pkt.pointee.pos
        if pos >= 0 {
            packetConnection[index] = connections.lastIndex { $0.start <= pos } ?? 0
        }
        return packetConnection[index] ?? 0
    }

    private var hasVideoStream: Bool {
        lock.lock(); defer { lock.unlock() }
        return hasVideo
    }

    /// Runs on the demux thread (inside FFmpeg's read callback).
    private func enqueueTapped(_ frame: TSAudioTap.Frame) {
        let duration = Double(frame.duration) / 90_000
        let key = frame.data.withUnsafeBytes { ContentHistory.key($0, salt: -2) }
        if tapRejoining {
            if history.time(of: key) != nil {
                // Replayed: skip it.
                countDuplicate()
                return
            }
            // Until the video has lined the new connection up, its timestamps mean nothing.
            // (Radio-only taps have no video to wait for and simply continue.)
            if !connections[tapConnection].decided && hasVideoStream { return }
            tapRejoining = false
        }
        // Without a timestamp (after a reconnect, until the next PES header) the audio simply
        // continues where it left off.
        let out = frame.pts.map { Double($0) / 90_000 - connections[tapConnection].cut } ?? tapNextOut
        guard let out else { return }
        if let last = lastTapOut, out < last + duration / 2, last - out < 60 {
            countDuplicate()
            return
        }
        lastTapOut = out
        tapNextOut = out + duration
        history.insert(key, time: out)

        let pts = Int64((out * 90_000).rounded())
        let packet = frame.data.withUnsafeBytes { raw in
            ffs_packet_from_bytes(raw.bindMemory(to: UInt8.self).baseAddress, Int32(frame.data.count), pts, frame.duration)
        }
        guard let packet else { return }
        if let tunerOutput {
            tunerOutput.packet(packet, input: Self.tappedAudioIndex, timeBase: AVRational(num: 1, den: 90_000))
            var p: UnsafeMutablePointer<AVPacket>? = packet
            av_packet_free(&p)
            return
        }
        lock.lock()
        let itemSerial = serial
        audioDemuxedUntil = max(audioDemuxedUntil, out)
        lock.unlock()
        audioQ.put(.packet(packet, serial: itemSerial))
    }
}
