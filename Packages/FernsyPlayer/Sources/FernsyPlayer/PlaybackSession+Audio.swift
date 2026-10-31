import AVFoundation
import CFFShim
import CoreMedia
import CoreVideo
import FernsyCore

/// The audio decoder thread: libavcodec, swresample to float32, and enqueuing samples.
extension PlaybackSession {
    // MARK: - Audio

    func audioMain() {
        var ctx: UnsafeMutablePointer<AVCodecContext>?
        var openedIndex: Int32 = -1
        var resampler = ffs_resampler_alloc()
        var formatDescription: CMAudioFormatDescription?
        var fdKey = (rate: Int32(0), channels: Int32(0))
        var nextPTS: Double?
        var mySerial = 0
        #if DEBUG
        let meter = AudioLevelMeter()
        #endif
        guard let frame = av_frame_alloc() else { return }

        defer {
            var f: UnsafeMutablePointer<AVFrame>? = frame
            av_frame_free(&f)
            ffs_resampler_free(&resampler)
            avcodec_free_context(&ctx)
        }

        func ensureDecoder() {
            lock.lock()
            let wanted = audioIndex
            lock.unlock()
            guard wanted != openedIndex else { return }
            avcodec_free_context(&ctx)
            openedIndex = wanted
            if wanted == Self.tappedAudioIndex {
                ctx = ffs_open_decoder_id(AV_CODEC_ID_AAC, AVRational(num: 1, den: 90_000))
            } else if let fmt, wanted >= 0, let st = fmt.pointee.streams[Int(wanted)] {
                ctx = ffs_open_decoder(st, 0)
            }
        }

        // Decoded audio collected into blocks of at least ~20 ms: TrueHD frames hold 40 samples
        // (0.83 ms), and a renderer fed over a thousand such buffers per second stays silent.
        var block = Data()
        var blockStart = 0.0
        var blockFrames = 0
        var blockKey = (rate: Int32(0), channels: Int32(0))

        func sendBlock() {
            guard blockFrames > 0 else { return }
            defer {
                block.removeAll(keepingCapacity: true)
                blockFrames = 0
            }
            if formatDescription == nil || fdKey != blockKey {
                formatDescription = Self.makeAudioFormat(rate: blockKey.rate, channels: blockKey.channels)
                fdKey = blockKey
            }
            let frames = blockFrames, start = blockStart, rate = blockKey.rate, channels = blockKey.channels
            guard let formatDescription,
                  let sample = block.withUnsafeBytes({ raw in
                      Self.makeAudioSample(data: raw.bindMemory(to: UInt8.self).baseAddress!, frames: frames, channels: Int(channels),
                                           rate: rate, pts: start, format: formatDescription)
                  }) else { return }
            enqueueAudio(sample, sec: start, duration: Double(frames) / Double(rate), serial: mySerial)
        }

        func present(_ f: UnsafeMutablePointer<AVFrame>) {
            guard let ctx, f.pointee.sample_rate > 0 else { return }
            let outChannels = ffs_output_channels(f.pointee.ch_layout.nb_channels)
            var data: UnsafePointer<UInt8>?
            let count = ffs_resample(resampler, f, outChannels, &data)
            guard count > 0, let data else { return }
            #if DEBUG
            if Self.logAudioLevel { meter.add(data, frames: Int(count), channels: Int(outChannels), rate: f.pointee.sample_rate) }
            #endif

            let rate = f.pointee.sample_rate
            let tb = ctx.pointee.pkt_timebase.num > 0 ? ctx.pointee.pkt_timebase : AVRational(num: 1, den: rate)
            var pts = f.pointee.best_effort_timestamp
            if pts == ffs_nopts() { pts = f.pointee.pts }
            var sec = pts != ffs_nopts() ? Double(pts) * av_q2d(tb) : (nextPTS ?? 0)
            // Containers with millisecond timestamps (MKV) round short frames – TrueHD's 40-sample
            // frames last 0.83 ms – so consecutive buffers would overlap and the renderer drops the
            // audio. Small deviations follow the sample count; only real jumps resync.
            if let expected = nextPTS, abs(sec - expected) < 0.05 { sec = expected }
            let duration = Double(count) / Double(rate)
            let continues = blockFrames > 0 && blockKey == (rate, outChannels)
                && abs(sec - (blockStart + Double(blockFrames) / Double(rate))) < 0.001
            if !continues {
                sendBlock()
                blockStart = sec
                blockKey = (rate, outChannels)
            }
            nextPTS = sec + duration
            block.append(data, count: Int(count) * Int(outChannels) * 4)
            blockFrames += Int(count)
            if blockFrames >= Int(rate) / 50 { sendBlock() }
        }

        func decode(_ pkt: UnsafeMutablePointer<AVPacket>?) {
            guard let ctx else { return }
            var sent = avcodec_send_packet(ctx, pkt)
            while true {
                while avcodec_receive_frame(ctx, frame) >= 0 {
                    present(frame)
                    av_frame_unref(frame)
                }
                guard sent == ffs_error_eagain() else { break }
                sent = avcodec_send_packet(ctx, pkt)
            }
        }

        ensureDecoder()
        while !isStopped {
            guard let item = audioQ.get() else { break }
            switch item {
            case .flush(let s):
                mySerial = s
                ensureDecoder()
                if let ctx { avcodec_flush_buffers(ctx) }
                nextPTS = nil
                block.removeAll(keepingCapacity: true)
                blockFrames = 0
                audioSink?.flush()
                audioRefillRequested = false
            case .eof(let s):
                guard s == mySerial else { continue }
                decode(nil)
                sendBlock()
                if let ctx { avcodec_flush_buffers(ctx) }
                lock.lock()
                audioDrained = true
                lock.unlock()
            case .packet(let pkt, let s):
                if s == mySerial { decode(pkt) }
                var p: UnsafeMutablePointer<AVPacket>? = pkt
                av_packet_free(&p)
            }
        }
    }

    #if DEBUG
    /// IPTV_AUDIOLEVEL=1: logs the peak level per channel once per second ("no sound" reports).
    private static let logAudioLevel = ProcessInfo.processInfo.environment["IPTV_AUDIOLEVEL"] == "1"

    private final class AudioLevelMeter {
        private var peaks: [Float] = []
        private var frames = 0

        func add(_ data: UnsafePointer<UInt8>, frames count: Int, channels: Int, rate: Int32) {
            if peaks.count != channels { peaks = Array(repeating: 0, count: channels) }
            data.withMemoryRebound(to: Float.self, capacity: count * channels) { samples in
                for i in 0..<(count * channels) { peaks[i % channels] = max(peaks[i % channels], abs(samples[i])) }
            }
            frames += count
            guard frames >= Int(rate) else { return }
            let db = peaks.map { $0 > 0 ? String(format: "%.0f", 20 * log10($0)) : "-inf" }.joined(separator: " ")
            debugLog("[test] audio peak dB [\(db)]")
            peaks = Array(repeating: 0, count: channels)
            frames = 0
        }
    }
    #endif

    private func enqueueAudio(_ sample: CMSampleBuffer, sec: Double, duration: Double, serial s: Int) {
        while true {
            lock.lock()
            if stopped || s != serial {
                lock.unlock()
                return
            }
            if prerolling {
                if startTime == nil {
                    if firstAudioPTS == nil { firstAudioPTS = sec }
                    if hasVideo {
                        // Let the first video frame define the start; audio before it is dropped.
                        lock.unlock()
                        Thread.sleep(forTimeInterval: 0.005)
                        continue
                    }
                    startTime = max(sec, prerollTarget ?? sec)
                }
                let start = startTime!
                if sec + duration <= start {
                    lock.unlock()
                    return
                }
                if audioEnqueuedUntil == -.infinity && sec > start + 0.3 { audioStartsLater = true }
                let ahead = sec - start
                lock.unlock()
                if ahead > 1.0 {
                    Thread.sleep(forTimeInterval: 0.005)
                    continue
                }
            } else {
                lock.unlock()
                let now = sync.currentTime().seconds
                if sec - now > 1.0 {
                    Thread.sleep(forTimeInterval: 0.01)
                    continue
                }
            }
            // Paced above (at most 1 s ahead), so the queue stays short without readiness checks.
            if case .suggestsFlush? = audioSink?.enqueue(sample), !audioRefillRequested {
                audioRefillRequested = true
                emit(.audioNeedsRefill)
            }
            lock.lock()
            audioEnqueuedUntil = max(audioEnqueuedUntil, sec + duration)
            lock.unlock()
            return
        }
    }

    private static func makeAudioFormat(rate: Int32, channels: Int32) -> CMAudioFormatDescription? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(rate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels) * 4, mFramesPerPacket: 1, mBytesPerFrame: UInt32(channels) * 4,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var layout = AudioChannelLayout()
        // FFmpeg's default 5.1 order is L R C LFE Ls Rs.
        layout.mChannelLayoutTag = channels == 6 ? kAudioChannelLayoutTag_MPEG_5_1_A : kAudioChannelLayoutTag_Stereo
        var fd: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: MemoryLayout<AudioChannelLayout>.size,
                                       layout: &layout, magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                       formatDescriptionOut: &fd)
        return fd
    }

    private static func makeAudioSample(data: UnsafePointer<UInt8>, frames: Int, channels: Int, rate: Int32,
                                        pts: Double, format: CMAudioFormatDescription) -> CMSampleBuffer? {
        let length = frames * channels * 4
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: length,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
              let block,
              CMBlockBufferReplaceDataBytes(with: data, blockBuffer: block, offsetIntoDestination: 0, dataLength: length) == noErr
        else { return nil }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames,
            presentationTimeStamp: CMTime(value: CMTimeValue((pts * Double(rate)).rounded()), timescale: rate),
            packetDescriptions: nil, sampleBufferOut: &sample)
        return sample
    }
}
