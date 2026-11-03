import AVFoundation
import CFFShim
import CoreMedia
import CoreVideo
import FernsyCore

/// The audio thread: AC-3 and E-AC-3 go to the system as a bitstream (apple-tv-surround design
/// 3); everything else, and a bitstream the system does not play, is decoded with libavcodec,
/// converted to float32 by swresample and enqueued as PCM.
extension PlaybackSession {
    // MARK: - Audio

    /// IPTV_AUDIOPASSTHROUGH=0: decode AC-3/E-AC-3 with FFmpeg as well.
    private static let passthroughAllowed = ProcessInfo.processInfo.environment["IPTV_AUDIOPASSTHROUGH"] != "0"
    #if DEBUG
    /// IPTV_TESTBITSTREAM=unplayable: the bitstream gets a format the system has no decoder for,
    /// to see the fallback to FFmpeg.
    private static let unplayableBitstreamTest = ProcessInfo.processInfo.environment["IPTV_TESTBITSTREAM"] == "unplayable"
    #else
    private static let unplayableBitstreamTest = false
    #endif

    func audioMain() {
        var ctx: UnsafeMutablePointer<AVCodecContext>?
        var openedIndex: Int32 = -1
        var resampler = ffs_resampler_alloc()
        var formatDescription: CMAudioFormatDescription?
        var fdKey = (rate: Int32(0), channels: Int32(0))
        var nextPTS: Double?
        var mySerial = 0
        // Bitstream: the stream's codec and time base, its format, and the checks for falling back.
        var bitstream: (codec: AVCodecID, timeBase: AVRational)?
        var bitstreamFormat: (format: CMAudioFormatDescription, key: Data)?
        var badPackets = 0
        var bitstreamStartedAt: Date?
        var bitstreamOff = false
        var reportedOutput = ""
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

        func reportOutput(_ text: String) {
            guard text != reportedOutput else { return }
            reportedOutput = text
            lock.lock()
            stats.audioOutput = text
            lock.unlock()
        }

        func ensureDecoder() {
            lock.lock()
            let wanted = audioIndex
            lock.unlock()
            guard wanted != openedIndex else { return }
            avcodec_free_context(&ctx)
            openedIndex = wanted
            bitstream = nil
            bitstreamFormat = nil
            bitstreamStartedAt = nil
            badPackets = 0
            reportedOutput = ""
            if wanted == Self.tappedAudioIndex {
                ctx = ffs_open_decoder_id(AV_CODEC_ID_AAC, AVRational(num: 1, den: 90_000))
            } else if let fmt, wanted >= 0, let st = fmt.pointee.streams[Int(wanted)] {
                let codec = st.pointee.codecpar.pointee.codec_id
                if Self.passthroughAllowed, !bitstreamOff, codec == AV_CODEC_ID_AC3 || codec == AV_CODEC_ID_EAC3 {
                    bitstream = (codec, st.pointee.time_base)
                    AppLog.info(.player, "audio: \(MediaNames.audioCodec(codec)) goes to the system as a bitstream")
                    #if DEBUG
                    if Self.logAudioLevel { debugLog("[test] audio level: not measured for a bitstream (IPTV_AUDIOPASSTHROUGH=0)") }
                    #endif
                } else {
                    ctx = ffs_open_decoder(st, 0)
                }
            }
        }

        /// The system could not play the bitstream: decode the track with FFmpeg for the rest of
        /// this playback, from the next packet on.
        func fallBack(_ reason: String) {
            guard bitstream != nil else { return }
            AppLog.warning(.player, "audio bitstream not played (\(reason)), decoding it with FFmpeg")
            bitstreamOff = true
            openedIndex = -1
            ensureDecoder()
            nextPTS = nil
            reportAudioFailure()
        }

        func sendBitstream(_ pkt: UnsafeMutablePointer<AVPacket>) {
            guard let bitstream, let data = pkt.pointee.data else { return }
            var info = FFSDolbyInfo()
            guard ffs_dolby_info(data, pkt.pointee.size, &info) == 0, info.sample_rate > 0, info.samples > 0 else {
                // Broken packets are skipped; a stream of them is not Dolby the system can play.
                badPackets += 1
                if badPackets >= 25 { fallBack("\(badPackets) packets without a valid Dolby header") }
                return
            }
            badPackets = 0
            let key = withUnsafeBytes(of: info.cookie) { Data($0.prefix(Int(info.cookie_size))) }
                + withUnsafeBytes(of: (info.sample_rate, info.channels, info.samples)) { Data($0) }
            if bitstreamFormat?.key != key {
                guard let format = Self.makeBitstreamFormat(codec: bitstream.codec, info: info, unplayable: Self.unplayableBitstreamTest) else {
                    fallBack("no format description")
                    return
                }
                bitstreamFormat = (format, key)
                let name = "\(MediaNames.audioCodec(bitstream.codec)) \(MediaNames.channels(info.channels))" + (info.atmos != 0 ? " Atmos" : "")
                reportOutput(String(localized: "Dolby bitstream (\(name))", bundle: .module))
            }
            let rate = info.sample_rate
            var sec = pkt.pointee.pts != ffs_nopts() ? Double(pkt.pointee.pts) * av_q2d(bitstream.timeBase) : (nextPTS ?? 0)
            if let expected = nextPTS, abs(sec - expected) < 0.05 { sec = expected }
            let duration = Double(info.samples) / Double(rate)
            nextPTS = sec + duration
            guard let format = bitstreamFormat?.format,
                  let sample = Self.makeBitstreamSample(data: data, size: Int(pkt.pointee.size), samples: Int(info.samples),
                                                        pts: sec, format: format) else { return }
            if enqueueAudio(sample, sec: sec, duration: duration, serial: mySerial) == .failed {
                fallBack("the renderer failed")
                return
            }
            // Accepted but never rendered while the clock runs: the system cannot play it.
            if sync.rate > 0, audioSink?.isRendering == false {
                if bitstreamStartedAt == nil { bitstreamStartedAt = Date() }
                if let started = bitstreamStartedAt, Date().timeIntervalSince(started) > 2 { fallBack("nothing rendered after 2 s") }
            } else if audioSink?.isRendering == true {
                bitstreamStartedAt = nil
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
            let outChannels = ffs_output_channels(f.pointee.ch_layout.nb_channels, AudioOutput.outputChannels)
            reportOutput("PCM \(MediaNames.channels(outChannels))")
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
                bitstreamStartedAt = nil
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
                if s == mySerial {
                    if bitstream != nil { sendBitstream(pkt) } else { decode(pkt) }
                }
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

    @discardableResult
    private func enqueueAudio(_ sample: CMSampleBuffer, sec: Double, duration: Double, serial s: Int) -> AudioSink.Outcome? {
        while true {
            lock.lock()
            if stopped || s != serial {
                lock.unlock()
                return nil
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
                    return nil
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
            let outcome = audioSink?.enqueue(sample)
            switch outcome {
            case .suggestsFlush?:
                if !audioRefillRequested {
                    audioRefillRequested = true
                    emit(.audioNeedsRefill)
                }
            // A failing bitstream falls back first (audio thread); its replacement comes from there.
            case .failed? where sample.formatDescription?.audioStreamBasicDescription?.mFormatID == kAudioFormatLinearPCM:
                reportAudioFailure()
            case .enqueued?:
                audioFailureReported = false
            default: break
            }
            lock.lock()
            audioEnqueuedUntil = max(audioEnqueuedUntil, sec + duration)
            lock.unlock()
            return outcome
        }
    }

    private static func makeAudioFormat(rate: Int32, channels: Int32) -> CMAudioFormatDescription? {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(rate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels) * 4, mFramesPerPacket: 1, mBytesPerFrame: UInt32(channels) * 4,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = pcmLayoutTag(channels: channels)
        var fd: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: MemoryLayout<AudioChannelLayout>.size,
                                       layout: &layout, magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                       formatDescriptionOut: &fd)
        return fd
    }

    /// Once until the next sample is taken again.
    private func reportAudioFailure() {
        guard !audioFailureReported else { return }
        audioFailureReported = true
        emit(.audioRendererFailed)
    }

    /// An AC-3/E-AC-3 format with the dac3/dec3 box as magic cookie (CoreAudio takes only the
    /// whole box) and the channel layout CoreAudio reads from it, as from an MP4 file.
    static func makeBitstreamFormat(codec: AVCodecID, info: FFSDolbyInfo, unplayable: Bool = false) -> CMAudioFormatDescription? {
        let formatID = unplayable ? 0x7473_7421 /* 'tst!' */ : codec == AV_CODEC_ID_EAC3 ? kAudioFormatEnhancedAC3 : kAudioFormatAC3
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(info.sample_rate), mFormatID: formatID,
            mFormatFlags: 0, mBytesPerPacket: 0, mFramesPerPacket: UInt32(info.samples), mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(info.channels), mBitsPerChannel: 0, mReserved: 0)
        var cookie = Data([0, 0, 0, UInt8(8 + info.cookie_size)])
        cookie.append(contentsOf: Array((codec == AV_CODEC_ID_EAC3 ? "dec3" : "dac3").utf8))
        cookie.append(withUnsafeBytes(of: info.cookie) { Data($0.prefix(Int(info.cookie_size))) })
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = bitstreamLayoutTag(asbd: asbd, cookie: cookie)
            ?? (info.channels == 6 ? kAudioChannelLayoutTag_MPEG_5_1_A : kAudioChannelLayoutTag_DiscreteInOrder | UInt32(info.channels))
        var fd: CMAudioFormatDescription?
        let status = cookie.withUnsafeBytes { raw in
            CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: MemoryLayout<AudioChannelLayout>.size, layout: &layout,
                                           magicCookieSize: raw.count, magicCookie: raw.baseAddress, extensions: nil, formatDescriptionOut: &fd)
        }
        return status == noErr ? fd : nil
    }

    /// The layout of the first format CoreAudio lists for the cookie (nil when it reads none).
    private static func bitstreamLayoutTag(asbd: AudioStreamBasicDescription, cookie: Data) -> AudioChannelLayoutTag? {
        cookie.withUnsafeBytes { raw -> AudioChannelLayoutTag? in
            var request = AudioFormatInfo(mASBD: asbd, mMagicCookie: raw.baseAddress!, mMagicCookieSize: UInt32(raw.count))
            var size: UInt32 = 0
            guard AudioFormatGetPropertyInfo(kAudioFormatProperty_FormatList, UInt32(MemoryLayout<AudioFormatInfo>.size), &request, &size) == noErr,
                  size >= UInt32(MemoryLayout<AudioFormatListItem>.size) else { return nil }
            var items = [AudioFormatListItem](repeating: AudioFormatListItem(), count: Int(size) / MemoryLayout<AudioFormatListItem>.size)
            guard AudioFormatGetProperty(kAudioFormatProperty_FormatList, UInt32(MemoryLayout<AudioFormatInfo>.size), &request, &size, &items) == noErr,
                  let tag = items.first?.mChannelLayoutTag, tag != 0 else { return nil }
            return tag
        }
    }

    /// One packet (its sync frames) as one compressed sample.
    static func makeBitstreamSample(data: UnsafePointer<UInt8>, size: Int, samples: Int, pts: Double,
                                    format: CMAudioFormatDescription) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: size, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: size,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
              let block,
              CMBlockBufferReplaceDataBytes(with: data, blockBuffer: block, offsetIntoDestination: 0, dataLength: size) == noErr
        else { return nil }
        let rate = Int32(format.audioStreamBasicDescription?.mSampleRate ?? 48_000)
        var packet = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(size))
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
            presentationTimeStamp: CMTime(value: CMTimeValue((pts * Double(rate)).rounded()), timescale: rate),
            packetDescriptions: &packet, sampleBufferOut: &sample)
        return sample
    }

    /// FFmpeg's default 5.1 order is L R C LFE Ls Rs; 7.1 comes reordered (`ffs_output_channels`).
    static func pcmLayoutTag(channels: Int32) -> AudioChannelLayoutTag {
        switch channels {
        case 8: kAudioChannelLayoutTag_MPEG_7_1_C
        case 6: kAudioChannelLayoutTag_MPEG_5_1_A
        default: kAudioChannelLayoutTag_Stereo
        }
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
